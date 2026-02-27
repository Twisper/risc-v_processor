/**
* @file adder.sv
* @brief A Kogge-Stone adder designed for high performance addition/subtraction of binary numbers.
*
* @author Mikhail Ulyanov, a.k.a Twisper
* @date Feb 2026
*
* @description
* This file implements adder, that implements Kogge-Stone scheme for arithmetic operations with signed and unsigned binary numbers.
*
* Key advantages:
* The main advantage of Kogge-Stone scheme over Ripple Carry Adder is minimization of critical path. 
* Kogge-Stone utilizes parallel prefix calculation. It allows to reduce combinational logic depth from linear O(N) to logarithmic O(Log2(N)).
*
* Interface:
* - Inputs: Two N-bit operands and Carry-In bit (used for subtractions operations).
* - Outputs: Sum and Carry-Out bit (indicates unsigned overflow).
* 
* Parameters:
* - WIDTH: Sets the bit-width of the operands (e.g. 64).
* - DEPTH: Determines the number of prefix stages (derived as $clog2(WIDTH))
*/

module adder
    #(parameter WIDTH = 64, parameter DEPTH = $clog2(WIDTH)) //Parameters for bit-width of the operands and number of prefix stages.
    (
    input   logic             carry_in, //Carry-In bit for subtractions.
    input   logic [WIDTH-1:0] a, b, //Two WIDTH-bit operands.
    output  logic [WIDTH-1:0] y, //Final Sum.
    output  logic             carry_out //Indicates unsigned overflow.
);

    genvar i, j;

    logic [DEPTH+1:0][WIDTH:0] g_level, p_level; //Packed arrays for generate (g) and propagate (p) prefix signals at each stage. 

    logic [WIDTH:0] a_carry, b_carry; //Operands with carry bit as first (zero) bit.

    generate
        assign a_carry = {a, carry_in}; // Prepending Carry-In as LSB to unify the carry chain logic. 
        assign b_carry = {b, carry_in};

        assign g_level[0] = a_carry & b_carry; //Calculating carry generating and propagation ability for every bit of operands (including Carry-In).
        assign p_level[0] = a_carry ^ b_carry;

        for (i = 1; i < DEPTH+2; i = i + 1) begin: stage_loop //Loop for every prefix stage.
            for (j = 0; j < WIDTH+1; j = j + 1) begin: bit_loop //Loop for every bit in future sum.

                if (j < 2**(i-1)) begin //If j is lower than 2**(i-1), it means that final carry for this bit is calculated. 

                    assign g_level[i][j] = g_level[i-1][j]; //Final carry for this bit is calculated, so we can move propagation and generation
                    assign p_level[i][j] = p_level[i-1][j]; //on next stage without concatenating with previous sets

                end else begin
                    /** 
                    * This branch concatenates carry bit propagation and generation of two sets. Every stage determines distance from current bit set
                    * to concatenating set. For example, first stage distance is 1, second is 2, third is 4, et cetera.
                    */

                    assign p_level[i][j] = p_level[i-1][j] & p_level[i-1][j-2**(i-1)];
                    assign g_level[i][j] = g_level[i-1][j] | (p_level[i-1][j] & g_level[i-1][j-2**(i-1)]);

                end
            end
        end
    endgenerate

    assign y = a ^ b ^ g_level[DEPTH+1][WIDTH-1:0]; //The final result is XOR between operands and carry bitmask.
    assign carry_out = g_level[DEPTH+1][WIDTH]; //Carry-Out bit is determined by the last bit from carry bitmask.

endmodule