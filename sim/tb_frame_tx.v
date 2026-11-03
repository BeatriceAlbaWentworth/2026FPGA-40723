// ============================================================
//  tb_frame_tx.v  —— 帧发送自测
//
//  缓冲区内容（spec.hex）和期望输出（tx_expected.hex）都是
//  Python 按协议 v3 生成的，所以这是"对着真协议"验证。
//
//  注：为了仿真快，tx_busy 只模拟 8 拍（真实是 540 拍），
//      字节内容不受影响。
// ============================================================
`timescale 1ns / 1ps

module tb_frame_tx;

    localparam integer NBYTES = 4134;
    localparam integer NBINS  = 513;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    // ---------------- 频谱缓冲（模拟 BRAM，1 拍延迟）----------------
    reg  [63:0] mem [0:NBINS-1];
    wire [9:0]  buf_addr;          // 由 DUT 输出驱动，必须是 wire
    reg  [63:0] buf_q;
    wire [63:0] buf_data;

    always @(posedge clk) buf_q <= mem[buf_addr];
    assign buf_data = buf_q;

    // ---------------- DUT ----------------
    reg         start = 1'b0;
    wire [7:0]  byte_data;
    wire        byte_valid;
    reg         tx_busy = 1'b0;
    wire        busy;
    wire        done;

    frame_tx #(
        .N_BINS  (NBINS),
        .SPEC_LEN(NBINS * 8),
        .TOTAL   (NBYTES)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .peak_bin    (16'd64),
        .peak_mag    (32'd4464008),
        .rms         (16'd6264),
        .status_code (8'd0),
        .ver         (8'd3),
        .frame_cnt   (16'd1),
        .buf_addr    (buf_addr),
        .buf_data    (buf_data),
        .byte_data   (byte_data),
        .byte_valid  (byte_valid),
        .tx_busy     (tx_busy),
        .busy        (busy),
        .done        (done)
    );

    // ---------------- 模拟 UART 忙 ----------------
    integer bc = 0;
    always @(posedge clk) begin
        if (byte_valid) begin
            tx_busy <= 1'b1;
            bc      <= 0;
        end else if (tx_busy) begin
            if (bc == 7) tx_busy <= 1'b0;
            else         bc <= bc + 1;
        end
    end

    // ---------------- 收集输出 ----------------
    reg [7:0] cap [0:NBYTES-1];
    reg [7:0] exp [0:NBYTES-1];
    integer   got = 0;

    always @(posedge clk) begin
        if (byte_valid && got < NBYTES) begin
            cap[got] = byte_data;
            got = got + 1;
        end
    end

    // ---------------- 主流程 ----------------
    integer i, errs, first_err;

    initial begin
        $readmemh("D:/zynq_vibration/proj/vib_pl/src/spec.hex", mem);
        $readmemh("D:/zynq_vibration/proj/vib_pl/src/tx_expected.hex", exp);

        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(negedge clk);

        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        while (!done) @(negedge clk);
        repeat (20) @(negedge clk);

        $display("---- 结果 ----");
        $display("  发出字节数 : %0d  (期望 %0d)", got, NBYTES);

        errs = 0;
        first_err = -1;
        for (i = 0; i < NBYTES; i = i + 1) begin
            if (cap[i] !== exp[i]) begin
                errs = errs + 1;
                if (first_err < 0) first_err = i;
            end
        end

        $display("  错误字节数 : %0d", errs);
        if (first_err >= 0) begin
            $display("  首个错误位置: %0d", first_err);
            $display("    期望 0x%02X  实际 0x%02X", exp[first_err], cap[first_err]);
        end

        if (got == NBYTES && errs == 0)
            $display("PASS: 输出帧与 Python 期望完全一致");
        else
            $display("FAIL");

        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
