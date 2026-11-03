// ============================================================
//  uart_tx.v  —— 串口发送（8N1）
// ============================================================
`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLKS_PER_BIT = 54
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,       // 拉高 1 拍即开始发送
    output reg        tx,
    output reg        busy
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            cnt     <= 16'd0;
            bit_idx <= 3'd0;
            shift   <= 8'd0;
            tx      <= 1'b1;
            busy    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        shift <= data;
                        cnt   <= 16'd0;
                        busy  <= 1'b1;
                        state <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt     <= 16'd0;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    tx <= shift[0];
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt   <= 16'd0;
                        shift <= {1'b0, shift[7:1]};
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt   <= 16'd0;
                        busy  <= 1'b0;
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
