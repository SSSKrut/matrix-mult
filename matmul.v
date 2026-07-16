// matmul — потоковый умножитель матриц C[M×N] = A[M×K] * B[K×N], int16.
//
// Обе входные матрицы подаются поэлементно (row-major) по независимым
// valid/ready-каналам. Когда обе загружены, модуль считает по одному
// MAC за такт и выдаёт элементы C row-major через выходной valid/ready.
// После выдачи последнего элемента модуль снова готов принимать данные.
//
// Выход полной ширины (2*DW + clog2(K) бит) — переполнение невозможно.
`timescale 1ns/1ps

module matmul #(
    parameter M  = 4,   // строки A и C
    parameter K  = 4,   // столбцы A = строки B
    parameter N  = 4,   // столбцы B и C
    parameter DW = 16
)(
    input  wire                             clk,
    input  wire                             rst,      // синхронный, активный высокий

    // матрица A, row-major
    input  wire                             a_valid,
    output wire                             a_ready,
    input  wire signed [DW-1:0]             a_data,

    // матрица B, row-major
    input  wire                             b_valid,
    output wire                             b_ready,
    input  wire signed [DW-1:0]             b_data,

    // результат C = A*B, row-major
    output wire                             c_valid,
    input  wire                             c_ready,
    output wire signed [2*DW+$clog2(K)-1:0] c_data
);
    localparam CW = 2*DW + $clog2(K);

    localparam [1:0] S_LOAD = 2'd0,
                     S_CALC = 2'd1,
                     S_EMIT = 2'd2;

    reg [1:0] state;

    reg signed [DW-1:0] a_mem [0:M*K-1];
    reg signed [DW-1:0] b_mem [0:K*N-1];

    reg [31:0] a_cnt, b_cnt;   // счётчики загрузки
    reg [31:0] i, j, k;        // индексы текущего элемента C и шаг MAC
    reg signed [CW-1:0] acc;

    wire a_done = (a_cnt == M*K);
    wire b_done = (b_cnt == K*N);

    assign a_ready = (state == S_LOAD) && !a_done;
    assign b_ready = (state == S_LOAD) && !b_done;
    assign c_valid = (state == S_EMIT);
    assign c_data  = acc;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_LOAD;
            a_cnt <= 0;
            b_cnt <= 0;
        end else begin
            case (state)
                S_LOAD: begin
                    if (a_valid && a_ready) begin
                        a_mem[a_cnt] <= a_data;
                        a_cnt <= a_cnt + 1;
                    end
                    if (b_valid && b_ready) begin
                        b_mem[b_cnt] <= b_data;
                        b_cnt <= b_cnt + 1;
                    end
                    if (a_done && b_done) begin
                        state <= S_CALC;
                        i <= 0;
                        j <= 0;
                        k <= 0;
                        acc <= 0;
                    end
                end

                S_CALC: begin
                    acc <= acc + a_mem[i*K + k] * b_mem[k*N + j];
                    if (k == K-1)
                        state <= S_EMIT;
                    else
                        k <= k + 1;
                end

                S_EMIT: if (c_ready) begin
                    acc <= 0;
                    k <= 0;
                    if (j == N-1) begin
                        j <= 0;
                        if (i == M-1) begin
                            state <= S_LOAD;
                            a_cnt <= 0;
                            b_cnt <= 0;
                        end else begin
                            i <= i + 1;
                            state <= S_CALC;
                        end
                    end else begin
                        j <= j + 1;
                        state <= S_CALC;
                    end
                end

                default: state <= S_LOAD;
            endcase
        end
    end
endmodule
