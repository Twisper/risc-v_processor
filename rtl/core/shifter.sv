/**
* @file shifter.sv
* @brief A universal shifter for RISC-V processors.
*
* @author Mikhail Ulyanov, a.k.a Twisper
* @date Feb 2026
*
* @description
* This file contains Barrel Shifter, which is able to do 5 types of shifting (Logical Left and Right, Arithmetic right, Rotate Left and Right from Zbb Extension) with 32 and 64 bit operands.
* Key advantages:
* - Universal and fast shifter for 5 types of shifts.
* - Uses only 575 Multiplexors (checked with yosys).
* - Is built for doing right shifts, but for left shifts reverses operand and result.
* - Supports 32-bit and 64-bit shifts at the same time. 
*
* Interface:
* - Inputs: One N-bit operand, shift distance, type of shift and direction
* - Outputs: N-bit result of shift
* 
* Parameters:
* - WIDTH: Sets the bit-width of the operand (e.g. 64).
* - DEPTH: Determines the number of shifting stages (derived as $clog2(WIDTH))
*/

import riscv_pkg::*;

module shifter
    #(parameter DEPTH = $clog2(WIDTH))
    (
    input   logic [WIDTH-1:0] operand_i, //operand to shift. 
    input   logic [DEPTH-1:0] shamt_i, //Shift distance. 
    input   logic [1:0]       shift_op_i, //Type of shifting. 00 - logical, 01 - arithmetical, 10 - rotation. 
    input   logic             shift_direction_i, //Direction of shift. 0 - left, 1 - right. 
    input   logic             is_32_bit_mode_i, //Puts shifter into 32-bit operand mode. 
    input   logic             unsigned_bit_i, //Bit for slli.uw instruction. 
    output  logic [WIDTH-1:0] result_o
);

    logic [DEPTH:0][WIDTH-1:0] temp; //Packed array to store results of each stage of shift. 
    logic [WIDTH-1:0]          concat_1, concat_2; //Temporary variables for left shifts. 
    logic [WIDTH-1:0]          new_operand, shift_result; //Variables for temporary input/output.
    logic [DEPTH-1:0]          shift;
    logic [1:0]                shift_type;
    genvar i;
    localparam int LOWWIDTH = WIDTH/2;

    /*
    * This always_comb block is nessesary for 32-bit operations (For example, SLLW, SRLW, SRAW, RORW, ROLW, etc.). 
    * Depending on shift operation, it extends high 32-bit operand to 64-bit, on order to make 32-bit and 64-bit operations similar. 
    */

    always_comb begin
        shift_type = shift_op_i;
        if (is_32_bit_mode_i) begin //Checking whether is 32-bit mode. 
            case (shift_op_i) //If yes, checking shift operation for higher bit extenion. 
                2'b00: new_operand = {{LOWWIDTH{1'b0}}, operand_i[LOWWIDTH-1:0]}; //If it is logical shift, higher bits become zeros. 
                2'b01: new_operand = {{LOWWIDTH{operand_i[LOWWIDTH-1]}}, operand_i[LOWWIDTH-1:0]}; //If it is arithmetic shift, extending higher bits with signed bit. 
                2'b10: begin
                    new_operand = {operand_i[LOWWIDTH-1:0], operand_i[LOWWIDTH-1:0]}; //It it is ROR/ROL shift, copying lower 32 bits into higher bits. 
                    shift_type = shift_direction_i ? 2'b00 : 2'b10;
                end 
                default: new_operand = {{LOWWIDTH{1'b0}}, operand_i[LOWWIDTH-1:0]}; //Default case - logical shift. 
            endcase
            shift = {1'b0, shamt_i[DEPTH-2:0]};
        end else begin
            new_operand = operand_i; //If it is 64-bit mode, doing nothing. 
            shift = shamt_i;
        end
    end

    reverse first_reverse (new_operand, concat_1); //If there is left shift, an operand is being reversed.  

    assign temp[0] = shift_direction_i ? new_operand : concat_1; //Direction bit affects, will be this reversed operand or not

    generate

        for (i = 1; i < DEPTH+1; i = i + 1) begin: stage_loop //Loop for every stage of shift (e.g. for 64 it will be 1, 2, 4, 8, 16, 32)

            localparam int SHAMT = 2**(i-1);

            /*
            * This ternary operator is needed to choose concatenations properly for logical, arithmetic and rotational shifts for each stage. 
            * For example, 00 shift type is right logical, 01 is right arithmetic, 10 is right rotation. 11 does not exist, so it is right logical.
            */

            assign temp[i] = (shift[i-1] == 1'b0) ? temp[i-1] :
                             (shift_type == 2'b10) ? // ROTATE Right
                                 { temp[i-1][SHAMT-1:0], temp[i-1][WIDTH-1:SHAMT] } :
                             (shift_type == 2'b01) ? // ARITHMETIC Right
                                 { {SHAMT{temp[i-1][WIDTH-1]}}, temp[i-1][WIDTH-1:SHAMT] } :
                             // LOGICAL Right (Default for 00 and 11)
                                 { {SHAMT{1'b0}}, temp[i-1][WIDTH-1:SHAMT] };
        end
    endgenerate

    reverse second_reverse (temp[DEPTH], concat_2); //If there is left shift, the result is being reversed.  

    assign shift_result = shift_direction_i ? temp[DEPTH] : concat_2; //Preparing final result for extension if it is 32-bit mode. 

    assign result_o = is_32_bit_mode_i ? (unsigned_bit_i ? {{LOWWIDTH{1'b0}}, shift_result[LOWWIDTH-1:0]} : {{LOWWIDTH{shift_result[LOWWIDTH-1]}}, shift_result[LOWWIDTH-1:0]}) : shift_result; //Extending final result with signed bit or zeros depending on unsigned bit for 64-bit register. 

endmodule

/**
 * @brief Helper module for bit reversal.
 *
 * @description
 * Used to convert Left Shift operations into Right Shift operations.
 * Note: Written using a generate loop because streaming operators {<<{}}
 * are not fully supported by Icarus Verilog and older Yosys versions.
 */

module reverse
    (
    input   logic [WIDTH-1:0] operand_i,
    output  logic [WIDTH-1:0] result_o
);

    genvar i;

    generate
        for (i = 0; i < WIDTH; i = i + 1) begin: bit_loop
            assign result_o[i] = operand_i[WIDTH-i-1];
        end
    endgenerate
endmodule