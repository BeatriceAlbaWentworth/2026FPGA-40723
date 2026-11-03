// ============================================================
//  frame_rx.v  —— 输入帧解析
//
//  把串口字节流解析成样本：
//    AA 55 | 10 | LEN(2B)=2048 | 1024×int16(小端) | CHK(2B)
//
//  输出：
//    sample/sample_valid  每个样本
//    sample_last          第 1024 个样本（给 FIR 产生 TLAST）
//    frame_start          收到帧头时的脉冲（顶层据此复位 FIR）
//    frame_done/frame_ok  校验结束及结果
// ============================================================
`timescale 1ns / 1ps

module frame_rx (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  byte_data,
    input  wire        byte_valid,

    output reg  [15:0] sample,
    output reg         sample_valid,
    output reg         sample_last,

    output reg         frame_start,
    output reg         frame_done,
    output reg         frame_ok
);

    localparam S_MAGIC1 = 4'd0;
    localparam S_MAGIC2 = 4'd1;
    localparam S_TYPE   = 4'd2;
    localparam S_LEN_LO = 4'd3;
    localparam S_LEN_HI = 4'd4;
    localparam S_DATA   = 4'd5;
    localparam S_CHK_LO = 4'd6;
    localparam S_CHK_HI = 4'd7;

    reg [3:0]  state;
    reg [15:0] byte_cnt;        // payload 已收字节数
    reg [15:0] len;             // payload 长度
    reg [15:0] sum;             // 累加和
    reg [7:0]  chk_lo;
    reg        byte_lo_flag;    // 当前是样本的低字节
    reg [7:0]  sample_lo;

    wire [15:0] sum_next = sum + {8'd0, byte_data};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_MAGIC1;
            byte_cnt     <= 16'd0;
            len          <= 16'd0;
            sum          <= 16'd0;
            chk_lo       <= 8'd0;
            byte_lo_flag <= 1'b1;
            sample       <= 16'd0;
            sample_valid <= 1'b0;
            sample_last  <= 1'b0;
            frame_start  <= 1'b0;
            frame_done   <= 1'b0;
            frame_ok     <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            sample_last  <= 1'b0;
            frame_start  <= 1'b0;
            frame_done   <= 1'b0;

            if (byte_valid) begin
                case (state)

                // ---------- 帧头 AA ----------
                S_MAGIC1: begin
                    if (byte_data == 8'hAA) begin
                        sum   <= {8'd0, byte_data};
                        state <= S_MAGIC2;
                    end
                end

                // ---------- 帧头 55 ----------
                S_MAGIC2: begin
                    if (byte_data == 8'h55) begin
                        sum         <= sum_next;
                        state       <= S_TYPE;
                        frame_start <= 1'b1;     // 通知顶层：可以复位 FIR 了
                    end else if (byte_data != 8'hAA) begin
                        state <= S_MAGIC1;       // 重新找帧头
                    end
                end

                // ---------- 帧类型 ----------
                S_TYPE: begin
                    sum <= sum_next;
                    if (byte_data == 8'h10) begin
                        state <= S_LEN_LO;
                    end else begin
                        state <= S_MAGIC1;       // 不是输入帧，丢弃
                    end
                end

                // ---------- 长度低字节 ----------
                S_LEN_LO: begin
                    sum  <= sum_next;
                    len  <= {len[15:8], byte_data};
                    state <= S_LEN_HI;
                end

                // ---------- 长度高字节 ----------
                S_LEN_HI: begin
                    sum      <= sum_next;
                    len      <= {byte_data, len[7:0]};
                    byte_cnt <= 16'd0;
                    byte_lo_flag <= 1'b1;
                    // 只接受 2048（1024 个 int16）
                    if ({byte_data, len[7:0]} == 16'd2048)
                        state <= S_DATA;
                    else
                        state <= S_MAGIC1;
                end

                // ---------- 1024 个样本 ----------
                S_DATA: begin
                    sum      <= sum_next;
                    byte_cnt <= byte_cnt + 1'b1;

                    if (byte_lo_flag) begin
                        sample_lo    <= byte_data;     // 低字节先到
                        byte_lo_flag <= 1'b0;
                    end else begin
                        byte_lo_flag <= 1'b1;
                        sample       <= {byte_data, sample_lo};
                        sample_valid <= 1'b1;
                        if (byte_cnt == 16'd2047)      // 最后一对字节
                            sample_last <= 1'b1;
                    end

                    if (byte_cnt == 16'd2047)
                        state <= S_CHK_LO;
                end

                // ---------- 校验低字节 ----------
                S_CHK_LO: begin
                    chk_lo <= byte_data;
                    state  <= S_CHK_HI;
                end

                // ---------- 校验高字节 ----------
                S_CHK_HI: begin
                    frame_done <= 1'b1;
                    frame_ok   <= ({byte_data, chk_lo} == sum);
                    state      <= S_MAGIC1;
                end

                default: state <= S_MAGIC1;
                endcase
            end
        end
    end

endmodule
