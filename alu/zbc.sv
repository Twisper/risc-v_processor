module bitcounter
    #(parameter WIDTH = 64)
    (
    input   logic [WIDTH-1:0] a,
    input   logic             is_32_bit_mode,
    output  logic [WIDTH-1:0] y
);

    logic                  [WIDTH-1:0] operand;
    logic [$clog2(WIDTH):0][WIDTH-1:0] step_results;
    genvar i, j, k;

    assign operand = is_32_bit_mode ? {32'b0, a[31:0]} : a;

    assign step_results[0] = operand;

    generate
        for (i = 1; i <= $clog2(WIDTH); i = i + 1) begin: stage_loop
            for (j = 0; j < (WIDTH / 2**i); j = j + 1) begin: summ_loop
                assign step_results[i][(i+1)*j+i:(i+1)*j] = step_results[i-1][2*i*j+i+(i-1):2*i*j+i] + step_results[i-1][2*i*j+(i-1):2*i*j];
            end
        end
    endgenerate
    assign y = {57'b0, step_results[$clog2(WIDTH)][6:0]};
endmodule