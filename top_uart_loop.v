// ============================================================
//  top_uart_loop.v  —— v1 固件：串口回环
//
//  收到的字节原样发回。用来验证：
//    1) 串口收发对不对
//    2) 波特率 921600 对不对
//    3) 帧格式能不能被 B 的 Python 解析
//
//  注意：这一版【不接 FIR/FFT】，只验证通信链路。
// ============================================================
`timescale 1ns / 1ps

module top_uart_loop #(
    parameter integer CLKS_PER_BIT = 54      // 50MHz / 921600 ≈ 54
)(
    input  wire clk,             // 50 MHz
    input  wire rst_n,           // 低有效复位
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire led              // 收到过数据就常亮，方便肉眼确认
);

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       tx_busy;

    reg  [7:0] tx_data;
    reg        tx_start;

    // ---------------- 收发器 ----------------
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx_pin),
        .data  (rx_data),
        .valid (rx_valid)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (tx_data),
        .start (tx_start),
        .tx    (uart_tx_pin),
        .busy  (tx_busy)
    );

    // ---------------- 16 深 FIFO ----------------
    // 串口收发速率相同，但必须缓一拍，否则连续字节会丢
    reg [7:0] mem [0:15];
    reg [3:0] wr_ptr, rd_ptr;
    reg [4:0] count;

    wire empty = (count == 5'd0);
    wire full  = (count == 5'd16);

    wire do_wr = rx_valid && !full;                  // 写入
    wire do_rd = !empty && !tx_busy && !tx_start;    // 读出并发送

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= 4'd0;
            rd_ptr   <= 4'd0;
            count    <= 5'd0;
            tx_data  <= 8'd0;
            tx_start <= 1'b0;
        end else begin
            tx_start <= 1'b0;                        // 默认单拍脉冲

            if (do_wr) begin
                mem[wr_ptr] <= rx_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            if (do_rd) begin
                tx_data  <= mem[rd_ptr];
                tx_start <= 1'b1;
                rd_ptr   <= rd_ptr + 1'b1;
            end

            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

    // ---------------- LED：收到过任意字节就点亮 ----------------
    reg seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)       seen <= 1'b0;
        else if (rx_valid) seen <= 1'b1;
    end
    assign led = seen;

endmodule
