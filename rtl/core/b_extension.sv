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
    input   logic [WIDTH-1:0] a, //Operand
    input   logic             is_32_bit_mode,
    output  logic [WIDTH-1:0] y //Result
);

    logic                  [WIDTH-1:0] operand;
    logic [$clog2(WIDTH):0][WIDTH-1:0] step_results; //Packed array for temporary storing sum of 2**N bits, where N is exact step
    localparam int HALF = WIDTH/2;
    genvar i, j, k;

    assign operand = is_32_bit_mode ? {{HALF{1'b0}}, a[HALF-1:0]} : a; //If there is cpopw instruction, upper half of operand is zero

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
    assign y = {57'b0, step_results[$clog2(WIDTH)][6:0]}; //Extending result to 64 bits.
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
    input   logic [WIDTH-1:0] operand,
    input   logic             oper_type, //0 - ctz, 1 - clz
    input   logic             is_32_bit_mode, //0 - 64 bit, 1 - 32 bit
    output  logic [WIDTH-1:0] y
);

    logic [WIDTH-1:0]           reversed_operand;
    logic [WIDTH-1:0]           a;
    logic [WIDTH/8 - 1:0]       valids; //An array of OR operation for each byte, each element shows, does at least one bit is "1"
    logic [WIDTH/8-1:0][2:0]    temp_cyphs; //Temporary variable for first step priority encoders. 
    logic [2:0]                 lower_half;
    logic [$clog2(WIDTH):0]     result;
    genvar i;

    reverse rev_operation (.a(operand), .y(reversed_operand)); //Reversing operand for clz instruction.

    assign a = is_32_bit_mode ? 
        (oper_type ? 
            {32'b1, reversed_operand[WIDTH-1:WIDTH/2]} :  //If it is 32-bit mode and clz (clzw), taking upper half of reversed operand as lower half and filling upper half with ones.
            {32'b1, operand[WIDTH/2-1:0]}) :          //If it is 32-bit mode and ctz (ctzw), taking lower half of unreversed operand and filling upper half with ones.
        (oper_type ?                    
            reversed_operand :          //If clz, taking reversed operand. 
            operand);                   //If ctz, doing nothing.

    generate
        for (i = 0; i < WIDTH / 8; i = i + 1) begin : cyph_loop
            prior_cyph_8_3 my_cyph (.a(a[i*8+7:i*8]), .y(temp_cyphs[i])); //Generating priority encryptors for each byte.
            assign valids[i] = | a[i*8+7:i*8]; //Checking whether is at least one "1" bit in byte and storing this value for second step encryptor.
        end
    endgenerate

    assign result[$clog2(WIDTH)] = ~| valids; //If there is no "1" bits, most significant bit is one, other ones will be zeros.

    prior_cyph_8_3 upper_res_hals (.a(valids), .y(result[5:3])); //Creating upper half of result with priority encryptor from array, which stores "1" bits in bytes checking.

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

    assign y = {57'b0, result}; //Extending 7-bit result to 64 bits. 

endmodule

/**
 * @brief Priority encryptor 3:8 module.
 *
 * @description
 * Returns position of first "1" bit in byte. 
 */

module prior_cyph_8_3
    (
    input   logic [7:0] a,
    output  logic [2:0] y
);

    always_comb begin
        casez (a)
            8'b10000000: y = 7;
            8'b?1000000: y = 6;
            8'b??100000: y = 5;
            8'b???10000: y = 4;
            8'b????1000: y = 3;
            8'b?????100: y = 2;
            8'b??????10: y = 1;
            8'b???????1: y = 0;
            default: y = 0;
        endcase
    end

endmodule