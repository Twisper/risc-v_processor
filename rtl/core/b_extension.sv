/**
* @file b_extension.sv
* @brief A "B" extension for RISC-V processors.
*
* @author Mikhail Ulyanov, a.k.a Twisper
* @date Feb 2026 - March 2026
*
* @description
* This file contains multiple modules, which implement:
* - "1" bits counter (cpop instruction)
* - Leading and trailing zeros counter (clz and ctz instructions)
* 
* Parameters:
* - WIDTH: Sets the bit-width of the operand (e.g. 64).
*/

/**
 * @brief "1" bits counter module for cpop instruction.
 *
 * @description
 * Builds summator tree in order to count all "1" bits in operand. 
 * Works with 32-bit and 64-bit operands. 
 * 
 * Interface:
 * - Inputs: An operand and 32-bit mode flag.
 * - Outputs: 7-bit result, extended to 64 bits.
*/

import riscv_pkg::*;

module bitcounter
    (
    input   logic [WIDTH-1:0] operand_i, //Operand
    input   logic             is_32_bit_mode_i,
    output  logic [WIDTH-1:0] result_o //Result
);

    logic                  [WIDTH-1:0] operand;
    logic [$clog2(WIDTH):0][WIDTH-1:0] step_results; //Packed array for temporary storing sum of 2**N bits, where N is exact step
    localparam int HALF = WIDTH/2;
    genvar i, j, k;

    assign operand = is_32_bit_mode_i ? {{HALF{1'b0}}, operand_i[HALF-1:0]} : operand_i; //If there is cpopw instruction, upper half of operand is zero

    assign step_results[0] = operand;

    /**
    * Every array contains sum of 2**N bitw, where N is number of current step. Generate block builds a tree of summators, which acts like this:
    * The first step summators finding sum for 2 neighbouring bits (the result is 2 bits, 0, 1 or 2), then storing result to step_results[1] array.
    * On second steps summators finding sum for two neighbouring 2-bit operands from previous step (the result is 3 bits, 0, 1, 2, 3 or 4), then storing result to step_results[2] array, etc. 
    * It continues to exact moment, until the result of all sums becomes log2(WIDTH)+1 bits. It means, that we've found final result.
    */

    generate
        for (i = 1; i <= $clog2(WIDTH); i = i + 1) begin: stage_loop
            for (j = 0; j < (WIDTH / 2**i); j = j + 1) begin: summ_loop
                assign step_results[i][(i+1)*j+i:(i+1)*j] = step_results[i-1][2*i*j+i+(i-1):2*i*j+i] + step_results[i-1][2*i*j+(i-1):2*i*j];
            end
        end
    endgenerate
    assign result_o = {57'b0, step_results[$clog2(WIDTH)][6:0]}; //Extending result to 64 bits.
endmodule

/**
 * @brief Leading and trailing zeros counter module for clz/ctz(w) instructions.
 *
 * @description
 * Is built primarly for ctz(w) instruction, but supports clz(w), reversing bit order of operand for that.
 * Uses priority encoders to construct two parts of result - upper and lower halves. The encoder on the first layer shows, on which position is first "1" bit.
 * The one priority encryptor on second layer builds upper half of result and chooses lower half with its own output as control signal for multiplexer.
 * 
 * Interface:
 * - Inputs: An operand, 32-bit mode flag, type of operation.
 * - Outputs: 7-bit result, extended to 64 bits.
*/

module zeroscounter
    (
    input   logic [WIDTH-1:0] operand_i,
    input   logic             oper_type_i, //0 - ctz, 1 - clz
    input   logic             is_32_bit_mode_i, //0 - 64 bit, 1 - 32 bit
    output  logic [WIDTH-1:0] result_o
);

    logic [WIDTH-1:0]           reversed_operand;
    logic [WIDTH-1:0]           a;
    logic [WIDTH/8 - 1:0]       valids; //An array of OR operation for each byte, each element shows, does at least one bit is "1"
    logic [WIDTH/8-1:0][2:0]    temp_cyphs; //Temporary variable for first step priority encoders. 
    logic [2:0]                 lower_half;
    logic [$clog2(WIDTH):0]     result;
    genvar i;

    reverse rev_operation (.operand_i(operand_i), .result_o(reversed_operand)); //Reversing operand for clz instruction.

    assign a = is_32_bit_mode_i ? 
        (oper_type_i ? 
            {32'b1, reversed_operand[WIDTH-1:WIDTH/2]} :  //If it is 32-bit mode and clz (clzw), taking upper half of reversed operand as lower half and filling upper half with ones.
            {32'b1, operand_i[WIDTH/2-1:0]}) :          //If it is 32-bit mode and ctz (ctzw), taking lower half of unreversed operand and filling upper half with ones.
        (oper_typ_i ?                    
            reversed_operand :          //If clz, taking reversed operand. 
            operand_i);                   //If ctz, doing nothing.

    generate
        for (i = 0; i < WIDTH / 8; i = i + 1) begin : cyph_loop
            prior_cyph_8_3 my_cyph (.a(a[i*8+7:i*8]), .result_o(temp_cyphs[i])); //Generating priority encryptors for each byte.
            assign valids[i] = | a[i*8+7:i*8]; //Checking whether is at least one "1" bit in byte and storing this value for second step encryptor.
        end
    endgenerate

    assign result[$clog2(WIDTH)] = ~| valids; //If there is no "1" bits, most significant bit is one, other ones will be zeros.

    prior_cyph_8_3 upper_res_hals (.a(valids), .result_o(result[5:3])); //Creating upper half of result with priority encryptor from array, which stores "1" bits in bytes checking.

    always_comb begin //Final multiplexer, which chooses lower half of result based on upper half.
        case (result[5:3])
            3'b000: lower_half = temp_cyphs[0];
            3'b001: lower_half = temp_cyphs[1];
            3'b010: lower_half = temp_cyphs[2];
            3'b011: lower_half = temp_cyphs[3];
            3'b100: lower_half = temp_cyphs[4];
            3'b101: lower_half = temp_cyphs[5];
            3'b110: lower_half = temp_cyphs[6];
            3'b111: lower_half = temp_cyphs[7];
            default: lower_half = temp_cyphs[7];
        endcase
    end

    assign result[2:0] = lower_half;

    assign result_o = {57'b0, result}; //Extending 7-bit result to 64 bits. 

endmodule

/**
 * @brief Priority encryptor 3:8 module.
 *
 * @description
 * Returns position of first "1" bit in byte. 
 */

module prior_cyph_8_3
    (
    input   logic [7:0] operand_i,
    output  logic [2:0] result_o
);

    always_comb begin
        casez (operand_i)
            8'b10000000: result_o = 7;
            8'b?1000000: result_o = 6;
            8'b??100000: result_o = 5;
            8'b???10000: result_o = 4;
            8'b????1000: result_o = 3;
            8'b?????100: result_o = 2;
            8'b??????10: result_o = 1;
            8'b???????1: result_o = 0;
            default: result_o = 0;
        endcase
    end

endmodule

/**
 * @brief Wrapper module for Carry-Less Multiplication. 
 *
 * @description
 * This module chooses right slices from 128-bit result of carry-less multiplication of two 64-bit operands.
 * Interface:
 * - Inputs: Two operands, and operation type (00 - clmul, 01 - clmulh, 10 - clmulr). 
 * - Outputs: 64-bit chosen result of concatenation.
*/

module clmult_wrapper
    (
    input   logic [WIDTH-1:0] operand_a_i,
    input   logic [WIDTH-1:0] operand_b_i,
    input   logic [1:0]       operation_type_i,
    output  logic [WIDTH-1:0] result_o
);

    logic [2*WIDTH-1:0] clmult_result;
    logic [WIDTH-1:0] final_result;

    clmult_karatsuba main_clmult ( //Calling module for carry-less multiplication.
                                  .operand_a_i(operand_a_i), 
                                  .operand_b_i(operand_b_i), 
                                  .result_o(clmult_result));

    always_comb begin
        case (operation_type_i)
            2'b00: final_result = clmult_result[WIDTH-1:0];
            2'b01: final_result = clmult_result[2*WIDTH-1:WIDTH];
            2'b10: final_result = clmult_result[2*WIDTH-2:WIDTH-1];
            default: final_result = clmult_result[WIDTH-1:0];
        endcase
    end

    assign result_o = final_result;

endmodule

/**
 * @brief Main module for Carry-Less Multiplication with Karatsuba's method.
 *
 * @description
 * This module chooses right slices from given operands using Karatsuba's method, recursively calling itself, until size of operand is 16 bit.
 * Then is uses matrix carry-less multiplication to reduce critical path. Then it constructs 16-bit product with formula and 128-bit result can be constructed after some layers of recursion with same formula.
 * The main advantage of this scheme, that it balances between speed and area on crystal, being nearly twice as smaller as 64x64 matrix multiplier and faster than 64x64 Karatsuba multiplier.
 * Interface:
 * - Inputs: two N-bit operands. 
 * - Outputs: 2*N-bit product.
*/

module clmult_karatsuba
    #(parameter SIZE = 64)
    (
    input   logic [SIZE-1:0] operand_a_i,
    input   logic [SIZE-1:0] operand_b_i,
    output  logic [2*SIZE-1:0] result_o
);

    logic [SIZE-1:0] P_HIGH, P_LOW, P_MIDDLE;

    /*
     * Karatsuba's method uses three results of multiplication of smaller operands
     * P_l = A_l * B_l, where A_l - lower part of operand A, B_l - lower part of operand B
     * P_h = A_h * B_h, where A_h - higher part of operand A, B_l - higher part of operand B
     * P_m = (A_h ^ A_l) * (B_h ^ B_l)
     * Because of that, the recursion can be used for finding products of slices (i.e. smaller operands), placing same modules on crystal. 
     * When all of three products are found, result consists of two XOR'ed parts - P_h and P_l concatenated and (P_h ^ P_m ^ P_l) as middle part. 
     * For example, if the the result is 32 bits, P_l will be 15:0 bits, P_h will be 31:16 bits ({P_h, P_l} is [31:0]), (P_h ^ P_m ^ P_l) will XOR [23:8] bits of concatenated P_h and P_l.
    */

    if (SIZE > 16) begin : gen_submodules
        //Calling recursively Karatsuba modules for P_l, P_m, P_h.
        clmult_karatsuba #(.SIZE(SIZE/2)) recursive_clmult_low (
                                                                .operand_a_i(operand_a_i[SIZE/2-1:0]), 
                                                                .operand_b_i(operand_b_i[SIZE/2-1:0]), 
                                                                .result_o(P_LOW));
        clmult_karatsuba #(.SIZE(SIZE/2)) recursive_clmult_middle (
                                                                .operand_a_i(operand_a_i[SIZE-1:SIZE/2] ^ operand_a_i[SIZE/2-1:0]), 
                                                                .operand_b_i(operand_b_i[SIZE-1:SIZE/2] ^ operand_b_i[SIZE/2-1:0]), 
                                                                .result_o(P_MIDDLE));
        clmult_karatsuba #(.SIZE(SIZE/2)) recursive_clmult_high (
                                                                .operand_a_i(operand_a_i[SIZE-1:SIZE/2]), 
                                                                .operand_b_i(operand_b_i[SIZE-1:SIZE/2]), 
                                                                .result_o(P_HIGH));

        assign result_o = {P_HIGH, P_LOW} ^ {{(SIZE/2){1'b0}}, (P_MIDDLE ^ P_LOW ^ P_HIGH), {(SIZE/2){1'b0}}}; //Constructing result.
    end else begin
        //Calling matrix modules for 16-bit operands. 
        clmult_matrix #(.SIZE(8)) base_clmult_low (
                                                    .operand_a_i(operand_a_i[7:0]), 
                                                    .operand_b_i(operand_b_i[7:0]), 
                                                    .result_o(P_LOW));
        clmult_matrix #(.SIZE(8)) base_clmult_middle (
                                                    .operand_a_i(operand_a_i[15:8] ^ operand_a_i[7:0]), 
                                                    .operand_b_i(operand_b_i[15:8] ^ operand_b_i[7:0]), 
                                                    .result_o(P_MIDDLE));
        clmult_matrix #(.SIZE(8)) base_clmult_high (
                                                    .operand_a_i(operand_a_i[15:8]), 
                                                    .operand_b_i(operand_b_i[15:8]), 
                                                    .result_o(P_HIGH));

        assign result_o = {P_HIGH, P_LOW} ^ {8'b0, (P_MIDDLE ^ P_LOW ^ P_HIGH), 8'b0}; //Constructing result.
    end

endmodule 

/**
 * @brief Matrix Carry-Less 8x8 multiplicator.
 *
 * @description
 * This module multiplies two 8-bit numbers and returns 16-bit result using matrix method.
 * Interface:
 * - Inputs: Two 8-bit operands. 
 * - Outputs: 16-bit product of multiplication.
*/

module clmult_matrix
    #(parameter SIZE = 8)
    (
    input   logic [SIZE-1:0] operand_a_i,
    input   logic [SIZE-1:0] operand_b_i,
    output  logic [2*SIZE-1:0] result_o
);

    logic [2*SIZE-2:0][SIZE-1:0] temp_results; //Temporary packed array, which stores bits for carry-less sum of each resulting bit.
    logic [2*SIZE-2:0]           final_result;
    genvar i,j;

    generate
        for (i = 0; i < 2*SIZE-1; i = i + 1) begin : bit_loop //Loop for every bit in operands.
            for (j = 0; j < SIZE; j = j + 1) begin : and_loop //Loop for multiplying every two bits.
                if (((i < SIZE-1) && (j > i)) || ((i > SIZE-1) && (j < i-SIZE+1))) begin
                    assign temp_results[i][j] = 1'b0; //If there is nothing to multiply (index out of range), there will be zero.
                end else begin
                    assign temp_results[i][j] = operand_a_i[i-j] & operand_b_i[j]; //Otherwise, multiplying two digits.
                end
            end
            assign final_result[i] = ^ temp_results[i]; //Finding sum for every resulting bit with XOR operations
        end
    endgenerate

    assign result_o = {1'b0, final_result}; //The result of 8x8 carry-less multiplication is 15 bit, concatenating it to 16 bits.

endmodule

module xperm8 
    (
    input   logic [WIDTH-1:0] operand_a_i,
    input   logic [WIDTH-1:0] operand_b_i,
    output  logic [WIDTH-1:0] result_o
);

    logic [WIDTH/8-1:0][7:0] mask_bits;
    logic [WIDTH/8-1:0][7:0] vector;
    logic [WIDTH/8-1:0][7:0] result_bytes;
    genvar i;

    assign mask_bits = operand_b_i;
    assign vector = operand_a_i;

    generate
        for (i = 0; i < WIDTH/8; i = i + 1) begin : byte_mux
            assign result_bytes[i] = (~| mask_bits[i][7:3]) ? vector[mask_bits[i][2:0]] : 8'b0;
        end
    endgenerate

    assign result_o = result_bytes;

endmodule

module xperm4 
    (
    input   logic [WIDTH-1:0] operand_a_i,
    input   logic [WIDTH-1:0] operand_b_i,
    output  logic [WIDTH-1:0] result_o
);

    logic [WIDTH/4-1:0][3:0] mask_bits;
    logic [WIDTH/4-1:0][3:0] vector;
    logic [WIDTH/4-1:0][3:0] result_bytes;
    genvar i;

    assign mask_bits = operand_b_i;
    assign vector = operand_a_i;

    generate
        for (i = 0; i < WIDTH/4; i = i + 1) begin : byte_mux
            assign result_bytes[i] = vector[mask_bits[i][3:0]];
        end
    endgenerate

    assign result_o = result_bytes;

endmodule