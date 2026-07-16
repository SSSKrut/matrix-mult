// Тестбенч matmul: случайные матрицы, случайные паузы valid,
// случайный backpressure по c_ready, сверка с эталонной моделью.
// Раунд 0 — стресс: все элементы = -32768 (худший случай аккумуляции).
//
// Весь код ТБ работает по negedge: DUT тактируется по posedge, поэтому
// в момент negedge все сигналы стабильны и нет гонок с NBA-обновлениями.
// Паттерн переносим между Icarus и Verilator (--timing).
`timescale 1ns/1ps

// В ТБ усечения $random до 16/1 бит намеренные.
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */

module tb_matmul;
    parameter M  = 3;
    parameter K  = 4;
    parameter N  = 2;
    parameter DW = 16;
    parameter ROUNDS = 50;

    localparam CW = 2*DW + $clog2(K);

    reg clk;
    reg rst;
    always #5 clk = ~clk;

    reg                  a_valid, b_valid, c_ready;
    reg signed [DW-1:0]  a_data, b_data;
    wire                 a_ready, b_ready, c_valid;
    wire signed [CW-1:0] c_data;

    matmul #(.M(M), .K(K), .N(N), .DW(DW)) dut (
        .clk(clk), .rst(rst),
        .a_valid(a_valid), .a_ready(a_ready), .a_data(a_data),
        .b_valid(b_valid), .b_ready(b_ready), .b_data(b_data),
        .c_valid(c_valid), .c_ready(c_ready), .c_data(c_data)
    );

    reg signed [DW-1:0] A [0:M*K-1];
    reg signed [DW-1:0] B [0:K*N-1];
    reg signed [63:0]   C [0:M*N-1];

    integer errors = 0;
    integer round;

    task randomize_inputs;
        integer x;
        begin
            for (x = 0; x < M*K; x = x + 1) A[x] = $random;
            for (x = 0; x < K*N; x = x + 1) B[x] = $random;
        end
    endtask

    task stress_inputs;
        integer x;
        begin
            for (x = 0; x < M*K; x = x + 1) A[x] = 16'sh8000;
            for (x = 0; x < K*N; x = x + 1) B[x] = 16'sh8000;
        end
    endtask

    task compute_expected;
        integer ii, jj, kk;
        reg signed [63:0] s;
        begin
            for (ii = 0; ii < M; ii = ii + 1)
                for (jj = 0; jj < N; jj = jj + 1) begin
                    s = 0;
                    for (kk = 0; kk < K; kk = kk + 1)
                        s = s + A[ii*K + kk] * B[kk*N + jj];
                    C[ii*N + jj] = s;
                end
        end
    endtask

    // Все задачи входят и выходят выровненными на negedge.
    // Хендшейк совершается на posedge между двумя negedge, поэтому
    // ready, увиденный на negedge, гарантированно действует на
    // следующем posedge.
    task feed_a;
        integer idx;
        begin
            for (idx = 0; idx < M*K; idx = idx + 1) begin
                while ($random & 1) @(negedge clk);
                a_valid = 1;
                a_data  = A[idx];
                while (!a_ready) @(negedge clk);
                @(negedge clk);
                a_valid = 0;
            end
        end
    endtask

    task feed_b;
        integer idx;
        begin
            for (idx = 0; idx < K*N; idx = idx + 1) begin
                while ($random & 1) @(negedge clk);
                b_valid = 1;
                b_data  = B[idx];
                while (!b_ready) @(negedge clk);
                @(negedge clk);
                b_valid = 0;
            end
        end
    endtask

    task check_c;
        integer idx;
        begin
            for (idx = 0; idx < M*N; idx = idx + 1) begin
                c_ready = ($random & 1);
                while (!(c_valid && c_ready)) begin
                    @(negedge clk);
                    c_ready = ($random & 1);
                end
                if (c_data !== C[idx]) begin
                    errors = errors + 1;
                    $display("FAIL round %0d: C[%0d] = %0d, ожидалось %0d",
                             round, idx, c_data, C[idx]);
                end
                @(negedge clk);
                c_ready = 0;
            end
        end
    endtask

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("tb_matmul.vcd");
            $dumpvars(0, tb_matmul);
        end

        clk = 0;
        rst = 1;
        a_valid = 0;
        b_valid = 0;
        c_ready = 0;
        a_data = 0;
        b_data = 0;

        repeat (4) @(negedge clk);
        rst = 0;
        @(negedge clk);

        for (round = 0; round < ROUNDS; round = round + 1) begin
            if (round == 0)
                stress_inputs;
            else
                randomize_inputs;
            compute_expected;
            fork
                feed_a;
                feed_b;
                check_c;
            join
        end

        if (errors == 0)
            $display("PASS: %0d раундов, M=%0d K=%0d N=%0d, CW=%0d",
                     ROUNDS, M, K, N, CW);
        else
            $display("FAIL: ошибок %0d", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
