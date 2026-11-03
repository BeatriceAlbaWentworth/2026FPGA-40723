// ============================================================
//  top_full.v  —— 完整系统顶层
//
//  串口收到 2055 字节 → 1024 样本 → FIR → FFT
//                     → 存 513 个频点 → 状态帧 + 频谱帧发回
//
//  CLKS_PER_BIT 是参数：真机 54（921600），仿真时可以改小加速。
// ============================================================
`timescale 1ns / 1ps

module top_full #(
    parameter integer CLKS_PER_BIT = 54
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire led
);

    localparam integer N_BINS = 513;

    // ---------------- 串口接收 ----------------
    wire [7:0] rx_byte;
    wire       rx_byte_v;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(uart_rx_pin),
        .data(rx_byte), .valid(rx_byte_v)
    );

    // ---------------- 帧解析 ----------------
    wire [15:0] smp;
    wire        smp_v, smp_last;
    wire        frame_start, frame_done, frame_ok;

    frame_rx u_frx (
        .clk(clk), .rst_n(rst_n),
        .byte_data(rx_byte), .byte_valid(rx_byte_v),
        .sample(smp), .sample_valid(smp_v), .sample_last(smp_last),
        .frame_start(frame_start), .frame_done(frame_done), .frame_ok(frame_ok)
    );

    // ---------------- DSP 复位控制 ----------------
    reg  [3:0] rst_cnt;
    reg        dsp_rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_cnt   <= 4'd0;
            dsp_rst_n <= 1'b0;
        end else if (frame_start) begin
            dsp_rst_n <= 1'b0;
            rst_cnt   <= 4'd10;
        end else if (rst_cnt != 4'd0) begin
            rst_cnt <= rst_cnt - 1'b1;
            if (rst_cnt == 4'd1)
                dsp_rst_n <= 1'b1;
        end
    end

    // ---------------- FIR + FFT ----------------
    wire        dsp_s_tready;
    wire        dsp_m_tvalid;
    wire [63:0] dsp_m_tdata;
    wire        dsp_m_tlast;

    top_dsp u_dsp (
        .clk(clk), .rst_n(dsp_rst_n),
        .s_tvalid(smp_v), .s_tdata(smp), .s_tlast(smp_last), .s_tready(dsp_s_tready),
        .m_tready(1'b1), .m_tvalid(dsp_m_tvalid), .m_tdata(dsp_m_tdata), .m_tlast(dsp_m_tlast)
    );

    // ---------------- 频谱缓冲 + 峰值检测 ----------------
    reg  [63:0] spec_mem [0:N_BINS-1];
    reg  [9:0]  wr_addr;
    reg  [63:0] rd_data;
    wire [9:0]  rd_addr = tx_buf_addr;

    always @(posedge clk) begin
        if (dsp_m_tvalid && (wr_addr < N_BINS))
            spec_mem[wr_addr] <= dsp_m_tdata;
        rd_data <= spec_mem[rd_addr];
    end

    reg [9:0]  bin_cnt;
    reg [31:0] best_mag;
    reg [15:0] best_bin;
    reg        cap_done;

    wire [31:0] d_re = dsp_m_tdata[31:0];
    wire [31:0] d_im = dsp_m_tdata[63:32];

    // |I| + |Q|（32 位有符号取绝对值再相加）
    wire [31:0] a_re = (d_re[31]) ? (~d_re + 32'd1) : d_re;
    wire [31:0] a_im = (d_im[31]) ? (~d_im + 32'd1) : d_im;
    wire [31:0] mag  = a_re + a_im;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_cnt   <= 10'd0;
            best_mag  <= 32'd0;
            best_bin  <= 16'd0;
            wr_addr   <= 10'd0;
            cap_done  <= 1'b0;
        end else if (frame_start) begin
            bin_cnt   <= 10'd0;
            best_mag  <= 32'd0;
            best_bin  <= 16'd0;
            wr_addr   <= 10'd0;
            cap_done  <= 1'b0;
        end else if (dsp_m_tvalid) begin
            wr_addr <= wr_addr + 1'b1;
            bin_cnt <= bin_cnt + 1'b1;

            // 跳过 bin 0（直流）
            if (bin_cnt != 10'd0 && mag > best_mag) begin
                best_mag <= mag;
                best_bin <= {6'd0, bin_cnt};
            end

            if (dsp_m_tlast) cap_done <= 1'b1;
        end
    end

    // ---------------- DSP 处理周期计数器（v3.1）----------------
    //  启动：帧头到达后的第一个样本进入 FIR（smp_v）
    //  停止：该帧最后一个 FFT 输出握手（dsp_m_tvalid && dsp_m_tlast）
    //  结果放到状态帧原保留字节 12~15，单位=时钟周期（50 MHz，20 ns/周期）
    reg        tmr_run;
    reg        tmr_armed;
    reg  [31:0] tmr_cnt;
    reg  [31:0] tmr_cycles;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmr_run    <= 1'b0;
            tmr_armed  <= 1'b0;
            tmr_cnt    <= 32'd0;
            tmr_cycles <= 32'd0;
        end else if (frame_start) begin
            tmr_armed <= 1'b1;          // 帧头到达，等待第一个样本
            tmr_run   <= 1'b0;
        end else if (tmr_armed && smp_v) begin
            tmr_armed <= 1'b0;          // 第一个样本：启动
            tmr_run   <= 1'b1;
            tmr_cnt   <= 32'd1;
        end else if (tmr_run) begin
            tmr_cnt <= tmr_cnt + 1'b1;
            if (dsp_m_tvalid && dsp_m_tlast) begin
                tmr_run    <= 1'b0;
                tmr_cycles <= tmr_cnt;  // 最后一个频点输出：锁存
            end
        end
    end

    // ---------------- 流水线排空延迟计数器（v3.2）----------------
    //  启动：第 1024 个样本进入 FIR（smp_last）
    //  停止：最后一个 FFT 输出握手（dsp_m_tvalid && dsp_m_tlast）
    //  这就是"最后一个输入 → 最后一个输出"的真实流水线延迟
    //  结果占用状态帧 offset 6~7（原 rms 字段，恒为 0，现改为 uint16 周期数）
    reg        drn_run;
    reg [15:0] drn_cnt;
    reg [15:0] tmr_drain;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drn_run   <= 1'b0;
            drn_cnt   <= 16'd0;
            tmr_drain <= 16'd0;
        end else if (smp_last) begin
            drn_run <= 1'b1;
            drn_cnt <= 16'd0;
        end else if (drn_run) begin
            if (drn_cnt != 16'hFFFF) drn_cnt <= drn_cnt + 1'b1;  // 饱和，不回绕
            if (dsp_m_tvalid && dsp_m_tlast) begin
                drn_run   <= 1'b0;
                tmr_drain <= drn_cnt;
            end
        end
    end

    // ---------------- 发送 ----------------
    reg  [15:0] frame_cnt;
    reg         tx_start;
    wire [9:0]  tx_buf_addr;
    wire [7:0]  tx_byte;
    wire        tx_byte_v, tx_busy, tx_busy_f, tx_done;

    frame_tx u_ftx (
        .clk(clk), .rst_n(rst_n), .start(tx_start),
        .peak_bin(best_bin), .peak_mag(best_mag), .rms(tmr_drain),
        .status_code(8'd0), .ver(8'd3), .frame_cnt(frame_cnt),
        .tmr_cycles(tmr_cycles),
        .buf_addr(tx_buf_addr), .buf_data(rd_data),
        .byte_data(tx_byte), .byte_valid(tx_byte_v), .tx_busy(tx_busy),
        .busy(tx_busy_f), .done(tx_done)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .data(tx_byte), .start(tx_byte_v), .tx(uart_tx_pin), .busy(tx_busy)
    );

    // ---------------- 主序列 ----------------
    localparam T_IDLE = 3'd0, T_WAIT = 3'd1, T_DLY = 3'd2, T_SEND = 3'd3;

    reg [2:0]  tstate;
    reg [7:0]  dly_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tstate    <= T_IDLE;
            tx_start  <= 1'b0;
            frame_cnt <= 16'd0;
            dly_cnt   <= 8'd0;
        end else begin
            tx_start <= 1'b0;
            case (tstate)
                T_IDLE: begin
                    if (smp_last) tstate <= T_WAIT;
                end
                T_WAIT: begin
                    if (cap_done) begin
                        dly_cnt <= 8'd16;
                        tstate  <= T_DLY;
                    end
                end
                T_DLY: begin
                    if (dly_cnt == 8'd0) begin
                        tx_start  <= 1'b1;
                        frame_cnt <= frame_cnt + 1'b1;
                        tstate    <= T_SEND;
                    end else begin
                        dly_cnt <= dly_cnt - 1'b1;
                    end
                end
                T_SEND: begin
                    if (tx_done) tstate <= T_IDLE;
                end
                default: tstate <= T_IDLE;
            endcase
        end
    end

    // ---------------- LED：收到过样本就常亮 ----------------
    reg led_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        led_r <= 1'b0;
        else if (smp_v)    led_r <= 1'b1;
    end
    assign led = led_r;

    // ---------------- ILA 调试核 ----------------
    //  上板排查用：Vivado Hardware Manager 里能抓这四根线的波形
    //  probe0 = 串口收到的字节      probe1 = 字节有效
    //  probe2 = FFT 输出有效        probe3 = 帧头到达
    ila_0 u_ila (
        .clk    (clk),
        .probe0 (rx_byte),
        .probe1 (rx_byte_v),
        .probe2 (dsp_m_tvalid),
        .probe3 (frame_start)
    );

endmodule
