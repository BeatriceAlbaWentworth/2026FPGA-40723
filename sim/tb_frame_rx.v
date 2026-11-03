// ============================================================
//  tb_frame_rx.v  —— 帧解析器自测
//
//  用 Python 按协议 v3 真实生成的一帧（2055 字节）喂进去：
//    AA 55 | 10 | 00 08 | 2048 字节样本 | CHK
//  检查：
//    1) 能解出 1024 个样本，且与 sine125.hex 逐点一致
//    2) sample_last 只在第 1024 个出现一次
//    3) 校验和通过（frame_ok = 1）
// ============================================================
`timescale 1ns / 1ps

module tb_frame_rx;

    localparam integer NBYTES = 2055;
    localparam integer NSAMP  = 1024;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    reg  [7:0]  byte_data;
    reg         byte_valid;

    wire [15:0] sample;
    wire        sample_valid;
    wire        sample_last;
    wire        frame_start;
    wire        frame_done;
    wire        frame_ok;

    frame_rx dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .byte_data   (byte_data),
        .byte_valid  (byte_valid),
        .sample      (sample),
        .sample_valid(sample_valid),
        .sample_last (sample_last),
        .frame_start (frame_start),
        .frame_done  (frame_done),
        .frame_ok    (frame_ok)
    );

    // ---------------- 数据 ----------------
    reg [7:0]  frm [0:NBYTES-1];
    reg [15:0] exp [0:NSAMP-1];
    reg [15:0] cap [0:NSAMP-1];

    integer nsamp  = 0;
    integer nlast  = 0;
    integer i, errs;

    always @(posedge clk) begin
        if (sample_valid && nsamp < NSAMP) begin
            cap[nsamp] = sample;
            nsamp = nsamp + 1;
        end
        if (sample_last) nlast = nlast + 1;
    end

    // ---------------- 主流程 ----------------
    initial begin
        $readmemh("D:/zynq_vibration/proj/vib_pl/src/frame_in.hex", frm);
        $readmemh("D:/zynq_vibration/proj/vib_pl/src/sine125.hex", exp);

        byte_data  = 8'd0;
        byte_valid = 1'b0;

        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(negedge clk);

        $display("---- 送入 %0d 字节 ----", NBYTES);
        for (i = 0; i < NBYTES; i = i + 1) begin
            @(negedge clk);
            byte_data  = frm[i];
            byte_valid = 1'b1;
            @(negedge clk);
            byte_valid = 1'b0;
            repeat (2) @(negedge clk);
        end

        repeat (20) @(negedge clk);

        $display("---- 结果 ----");
        $display("  收到样本数   : %0d  (期望 %0d)", nsamp, NSAMP);
        $display("  sample_last  : %0d 次 (期望 1 次)", nlast);
        $display("  frame_done   : %b", frame_done);
        $display("  frame_ok     : %b  (期望 1)", frame_ok);
        $display("  前3个样本    : %0d %0d %0d", $signed(cap[0]), $signed(cap[1]), $signed(cap[2]));

        errs = 0;
        for (i = 0; i < NSAMP; i = i + 1)
            if (cap[i] !== exp[i]) errs = errs + 1;

        $display("  逐点比对错误 : %0d 个", errs);

        if (nsamp == NSAMP && nlast == 1 && frame_ok === 1'b1 && errs == 0)
            $display("PASS: 帧解析完全正确");
        else
            $display("FAIL");

        $finish;
    end

    initial begin
        #2_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
