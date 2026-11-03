// ============================================================
//  frame_tx.v  —— 结果帧发送（状态帧 + 频谱帧）
//
//  总字节数固定 = 23 + 4111 = 4134：
//    状态帧:  AA 55 02 | 10 00 | 16字节payload | CHK(2)
//    频谱帧:  AA 55 01 | 08 10 | 4104字节payload | CHK(2)
//
//  用一个全局字节计数器 gi 直接映射出该发哪个字节，逻辑简单不易错。
// ============================================================
`timescale 1ns / 1ps

module frame_tx #(
    parameter integer N_BINS    = 513,
    parameter integer SPEC_LEN  = 4104,     // N_BINS * 8
    parameter integer TOTAL     = 4134      // 23 + 4111
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire [15:0] peak_bin,
    input  wire [31:0] peak_mag,
    input  wire [15:0] rms,
    input  wire [7:0]  status_code,
    input  wire [7:0]  ver,
    input  wire [15:0] frame_cnt,
    input  wire [31:0] tmr_cycles,   // v3.1：DSP 处理周期数（占用原保留字节 12~15）

    output reg  [9:0]  buf_addr,
    input  wire [63:0] buf_data,

    output reg  [7:0]  byte_data,
    output reg         byte_valid,
    input  wire        tx_busy,

    output reg         busy,
    output reg         done
);

    localparam P_PULSE = 2'd0;
    localparam P_ACPT  = 2'd1;
    localparam P_WAIT  = 2'd2;

    reg [1:0]  ph;
    reg [1:0]  ld_cnt;
    reg [12:0] gi;
    reg [15:0] sum;
    reg        running;

    reg [7:0]  stb [0:15];

    // ---------------- 当前位置解码 ----------------
    wire        in_status  = (gi < 13'd23);
    wire [12:0] si         = gi - 13'd23;                  // 频谱帧内偏移
    wire [12:0] st_off     = gi - 13'd5;                   // 状态帧 payload 偏移
    wire [12:0] sp_off     = si - 13'd5;                   // 频谱帧 payload 偏移

    wire        st_hdr     = in_status && (gi < 13'd5);
    wire        st_pay     = in_status && (gi >= 13'd5) && (gi < 13'd21);
    wire        st_chk     = in_status && (gi >= 13'd21);
    wire        sp_hdr     = !in_status && (si < 13'd5);
    wire        sp_pay     = !in_status && (si >= 13'd5) && (si < 13'd4109);
    wire        sp_chk     = !in_status && (si >= 13'd4109);

    wire [2:0]  byte_in_bin = sp_off[2:0];
    wire [31:0] spe_re      = buf_data[31:0];
    wire [31:0] spe_im      = buf_data[63:32];

    // ---------------- 当前字节的值 ----------------
    reg [7:0] cur;
    always @(*) begin
        if (st_hdr) begin
            case (gi[2:0])
                3'd0: cur = 8'hAA;
                3'd1: cur = 8'h55;
                3'd2: cur = 8'h02;
                3'd3: cur = 8'd16;          // LEN 低字节
                default: cur = 8'd0;        // LEN 高字节
            endcase
        end else if (st_pay) begin
            cur = stb[st_off[3:0]];
        end else if (st_chk) begin
            cur = (gi[0] == 1'b1) ? sum[7:0] : sum[15:8];   // 先低字节
        end else if (sp_hdr) begin
            case (si[2:0])
                3'd0: cur = 8'hAA;
                3'd1: cur = 8'h55;
                3'd2: cur = 8'h01;
                3'd3: cur = SPEC_LEN_LO;
                default: cur = SPEC_LEN_HI;
            endcase
        end else if (sp_pay) begin
            case (byte_in_bin)
                3'd0: cur = spe_re[7:0];
                3'd1: cur = spe_re[15:8];
                3'd2: cur = spe_re[23:16];
                3'd3: cur = spe_re[31:24];
                3'd4: cur = spe_im[7:0];
                3'd5: cur = spe_im[15:8];
                3'd6: cur = spe_im[23:16];
                default: cur = spe_im[31:24];
            endcase
        end else begin
            cur = (si[0] == 1'b1) ? sum[7:0] : sum[15:8];   // 先低字节
        end
    end

    // 4104 = 0x1008 → 低字节 0x08、高字节 0x10
    wire [7:0] SPEC_LEN_LO = SPEC_LEN[7:0];
    wire [7:0] SPEC_LEN_HI = SPEC_LEN[15:8];

    // 当前字节是否计入校验（帧头 + payload）
    wire is_data = st_hdr | st_pay | sp_hdr | sp_pay;

    // ---------------- 主状态机 ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph         <= P_PULSE;
            ld_cnt     <= 2'd0;
            gi         <= 13'd0;
            sum        <= 16'd0;
            running    <= 1'b0;
            busy       <= 1'b0;
            done       <= 1'b0;
            byte_data  <= 8'd0;
            byte_valid <= 1'b0;
            buf_addr   <= 10'd0;
        end else begin
            byte_valid <= 1'b0;
            done       <= 1'b0;

            // 状态帧 16 字节（一直保持）
            stb[0]  <= peak_bin[7:0];
            stb[1]  <= peak_bin[15:8];
            stb[2]  <= peak_mag[7:0];
            stb[3]  <= peak_mag[15:8];
            stb[4]  <= peak_mag[23:16];
            stb[5]  <= peak_mag[31:24];
            stb[6]  <= rms[7:0];
            stb[7]  <= rms[15:8];
            stb[8]  <= status_code;
            stb[9]  <= ver;
            stb[10] <= frame_cnt[7:0];
            stb[11] <= frame_cnt[15:8];
            // v3.1：原保留字节改为 DSP 处理周期数（小端 uint32）
            stb[12] <= tmr_cycles[7:0];
            stb[13] <= tmr_cycles[15:8];
            stb[14] <= tmr_cycles[23:16];
            stb[15] <= tmr_cycles[31:24];

            if (start && !running) begin
                running  <= 1'b1;
                busy     <= 1'b1;
                gi       <= 13'd0;
                sum      <= 16'd0;
                ph       <= P_PULSE;
                buf_addr <= 10'd0;
            end else if (running) begin
                case (ph)

                P_PULSE: begin
                    if (ld_cnt != 2'd0) begin
                        // 等待 BRAM 读数据稳定（每个新频点前停 2 拍）
                        ld_cnt <= ld_cnt - 1'b1;
                    end else if (!tx_busy) begin
                        byte_data  <= cur;
                        byte_valid <= 1'b1;
                        if (is_data) sum <= sum + {8'd0, cur};
                        ph <= P_ACPT;
                    end
                end

                P_ACPT: begin
                    if (tx_busy) ph <= P_WAIT;
                end

                P_WAIT: begin
                    if (!tx_busy) begin
                        ph <= P_PULSE;
                        if (gi == TOTAL - 1) begin
                            running <= 1'b0;
                            busy    <= 1'b0;
                            done    <= 1'b1;
                            gi      <= 13'd0;
                        end else begin
                            gi <= gi + 1'b1;
                            // 状态帧结束、频谱帧开始时，校验和清零重新累加
                            if (gi == 13'd22) sum <= 16'd0;
                            // 频谱 payload：每跨到一个新频点，更新读地址并等待 BRAM
                            if (!in_status && (si + 13'd1 >= 13'd5) &&
                                ((si + 13'd1) < 13'd4109) &&
                                (((si + 13'd1 - 13'd5) & 13'h7) == 13'h0)) begin
                                buf_addr <= (si + 13'd1 - 13'd5) >> 3;
                                ld_cnt   <= 2'd2;
                            end
                        end
                    end
                end

                default: ph <= P_PULSE;
                endcase
            end
        end
    end

endmodule
