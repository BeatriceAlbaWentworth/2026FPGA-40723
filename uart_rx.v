// ============================================================
//  uart_rx.v  —— 串口接收（8N1）
//  50 MHz 时钟 / 921600 波特 → 分频 54（误差 +0.47%，可接受）
// ============================================================
`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLKS_PER_BIT = 54
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid        // 收到一个字节时拉高 1 拍
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;
    reg        rx_meta, rx_sync;

    // 两级同步，消除亚稳态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            cnt     <= 16'd0;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
            data    <= 8'd0;
            valid   <= 1'b0;
        end else begin
            valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (!rx_sync) begin
                        cnt   <= 16'd0;
                        state <= S_START;
                    end
                end

                S_START: begin
                    // 半位后采样，确认真的是起始位（排除毛刺）
                    if (cnt == (CLKS_PER_BIT / 2) - 1) begin
                        if (!rx_sync) begin
                            cnt     <= 16'd0;
                            bit_idx <= 3'd0;
                            state   <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt   <= 16'd0;
                        shift <= {rx_sync, shift[7:1]};   // LSB 先到
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        data  <= shift;
                        valid <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
