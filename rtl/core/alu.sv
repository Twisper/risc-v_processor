/**
 * @file alu.sv
 * @brief An arithmetical-logical unit for RISC-V processors.
 * 
 * @author Mikhail Ulyanov, a.k.a Twisper
 * @date Feb 2026 - March 2026
 *
 * @description
 * This file contains arithmetical-logical unit for RISC-V processors. It supports all instructions from RV64I and RV64B. 
 *
 * Interface:
 * - Inputs: 
 * - Two N-bit operands for operations
 * - Type of operation
 *
 * - Outputs: 
 * - N-bit result of operation.
 * - Flag of two operands equality.
 * - Flag of operands comparison (shows, if operand a is greater than operand b). 
*/

`default_nettype none
import riscv_pkg::*;

module alu
    (
    input   op_alu_e          operation_type_i,        
    input   logic [WIDTH-1:0] operand_a_i, 
    input   logic [WIDTH-1:0] operand_b_i,
    output  logic [WIDTH-1:0] adder_result_o,
    output  logic [WIDTH-1:0] result_o,
    output  logic             is_equal_o,
    output  logic             comparison_result_o
);

                ///////////
                // Adder //
                ///////////

    logic             sh1add_operand_a_flag;
    logic             sh2add_operand_a_flag;
    logic             sh3add_operand_a_flag;
    logic             uw_operand_a_flag;
    logic             negate_operand_b_flag;
    logic [WIDTH-1:0] extended_operand_a;
    logic [WIDTH-1:0] negated_operand_b;
    logic [WIDTH-1:0] adder_operand_a;
    logic [WIDTH-1:0] adder_operand_b;
    logic [WIDTH-1:0] adder_result;

    always_comb begin

        negate_operand_b_flag = 1'b0;
        sh1add_operand_a_flag = 1'b0;
        sh2add_operand_a_flag = 1'b0;
        sh3add_operand_a_flag = 1'b0;
        uw_operand_a_flag = 1'b0;

        unique case (operation_type_i)
            ALU_ADDUW,
            ALU_SH1ADDUW,
            ALU_SH2ADDUW,
            ALU_SH3ADDUW: uw_operand_a_flag = 1'b1;
            default: uw_operand_a_flag = 1'b0;
        endcase

        unique case (operation_type_i)
            ALU_SUB,
            ALU_EQ,  ALU_NE,
            ALU_LT,  ALU_LTU,
            ALU_GE,  ALU_GEU,
            ALU_MIN, ALU_MINU,
            ALU_MAX, ALU_MAXU: negate_operand_b_flag = 1'b1;

            ALU_SH1ADD, ALU_SH1ADDUW: sh1add_operand_a_flag = 1'b1;
            ALU_SH2ADD, ALU_SH2ADDUW: sh2add_operand_a_flag = 1'b1;
            ALU_SH3ADD, ALU_SH3ADDUW: sh3add_operand_a_flag = 1'b1;

            default:;
        endcase
    end

    //Preparing operand_a
    always_comb begin
        unique case (1'b1)
            uw_operand_a_flag: extended_operand_a = {{WIDTH/2{1'b0}}, operand_a_i[WIDTH/2-1:0]};
            default: extended_operand_a = operand_a_i;
        endcase
        unique case (1'b1)
            sh1add_operand_a_flag: adder_operand_a = {extended_operand_a[WIDTH-2:0], 1'b0};
            sh2add_operand_a_flag: adder_operand_a = {extended_operand_a[WIDTH-3:0], 2'b0};
            sh3add_operand_a_flag: adder_operand_a = {extended_operand_a[WIDTH-4:0], 3'b0};
            default: adder_operand_a = extended_operand_a;
        endcase
    end

    //Preparing operand_b
    assign negated_operand_b = {WIDTH{1'b1}} ^ operand_b_i;
    always_comb begin
        unique case (1'b1)
            negate_operand_b_flag: adder_operand_b = negated_operand_b;
            default: adder_operand_b = operand_b_i;
        endcase
    end

    logic             carry_out;

    adder kogge_stone_adder (
                .carry_in_i(negate_operand_b_flag), 
                .operand_a_i(adder_operand_a), 
                .operand_b_i(adder_operand_b), 
                .result_o(adder_result), 
                .carry_out_o(carry_out));

    assign adder_result_o = adder_result;

                ////////////////
                // Comparison //
                ////////////////

    logic is_equal;
    logic is_greater_or_equal;
    logic cmp_signed;
    
    always_comb begin

        cmp_signed = 1'b0;

        unique case (operation_type_i)
        ALU_LT,
        ALU_GE,
        ALU_SLT,
        ALU_MIN,
        ALU_MAX: cmp_signed = 1'b1;
        default: cmp_signed = 1'b0;
        endcase
    end

    assign is_equal_o = ~| adder_result;

    always_comb begin
        if (adder_operand_a[WIDTH-1] ^ adder_operand_b[WIDTH-1] == 1'b0) begin
            is_greater_or_equal = (adder_result[WIDTH-1] == 1'b0);
        end else begin
            is_greater_or_equal = operand_a_i[WIDTH-1] ^ cmp_signed;
        end
    end

    logic cmp_result;

    always_comb begin
        unique case (operation_type_i)
            ALU_EQ:             cmp_result = is_equal;
            ALU_NE:             cmp_result = ~ is_equal;

            ALU_GE, ALU_GEU,
            ALU_MAX, ALU_MAXU:  cmp_result = is_greater_or_equal;

            ALU_LT, ALU_LTU,
            ALU_MIN, ALU_MINU,
            ALU_SLT, ALU_SLTU:  cmp_result = ~ is_greater_or_equal;

            default:;
        endcase
    end

    assign comparison_result_o = cmp_result;

                /////////////
                // Shifter //
                /////////////

    logic                       shifter_32_bit_mode;
    shift_op_e                  shifter_operation;
    shift_dir_e                 shifter_direction;
    logic [$clog2(WIDTH)-1:0]   shamt;
    logic [WIDTH-1:0]           shifter_operand; 
    logic [WIDTH-1:0]           shifter_result;

    assign shamt = operand_b_i[$clog2(WIDTH)-1:0];

    always_comb begin
        unique case (operation_type_i)

            ALU_SLLUW: shifter_operand = {{WIDTH/2{1'b0}}, operand_a_i[WIDTH/2-1:0]};

            ALU_BINV, ALU_BSET, ALU_BCLR: shifter_operand = {{WIDTH-1{1'b0}}, 1'b1};

            default: shifter_operand = operand_a_i;
        endcase

        unique case (operation_type_i)

            ALU_SLLW,
            ALU_SRLW, ALU_SRAW,
            ALU_ROLW, ALU_RORW: shifter_32_bit_mode = 1'b1;

            default: shifter_32_bit_mode = 1'b0;
        endcase

        unique case (operation_type_i)

            ALU_SLL, ALU_SLLW, 
            ALU_SLLUW,
            ALU_ROL, ALU_ROLW,
            ALU_BINV, ALU_BSET, ALU_BCLR: shifter_direction = SHIFT_LEFT;

            default: shifter_direction = SHIFT_RIGHT;

        endcase

        unique case (operation_type_i)

            ALU_SRA, ALU_SRAW: shifter_operation = SHIFT_ARITHMETICAL;

            ALU_ROL, ALU_ROLW,
            ALU_ROR, ALU_RORW: shifter_operation = SHIFT_ROTATE;

            default: shifter_operation = SHIFT_LOGICAL;

        endcase
    end

    shifter barrel_shifter (
                            .operand_i(shifter_operand), 
                            .shamt_i(shamt), 
                            .shift_op_i(shifter_operation), 
                            .shift_direction_i(shifter_direction), 
                            .is_32_bit_mode_i(shifter_32_bit_mode), 
                            .result_o(shifter_result));

                /////////////
                // Bitwise //
                /////////////

    logic             bwlogic_or;
    logic             bwlogic_and;
    logic [WIDTH-1:0] bwlogic_operand_b;
    logic [WIDTH-1:0] bwlogic_or_result;
    logic [WIDTH-1:0] bwlogic_and_result;
    logic [WIDTH-1:0] bwlogic_xor_result;
    logic [WIDTH-1:0] bwlogic_result;

    logic bwlogic_operand_b_negate;

    always_comb begin
        unique case (operation_type_i)
            ALU_ANDN,
            ALU_ORN,
            ALU_XORN: bwlogic_operand_b_negate = 1'b1;
            default: bwlogic_operand_b_negate = 1'b0;
        endcase
    end

    assign bwlogic_operand_b = bwlogic_operand_b_negate ? ~operand_b_i : operand_b_i;

    assign bwlogic_and_result = operand_a_i & bwlogic_operand_b;
    assign bwlogic_or_result = operand_a_i | bwlogic_operand_b;
    assign bwlogic_xor_result = operand_a_i ^ bwlogic_operand_b;

    assign bwlogic_and = (operation_type_i == ALU_AND) | (operation_type_i == ALU_ANDN);
    assign bwlogic_or = (operation_type_i == ALU_OR) | (operation_type_i == ALU_ORN);

    always_comb begin
        unique case (1'b1)
        bwlogic_and: bwlogic_result = bwlogic_and_result;
        bwlogic_or: bwlogic_result = bwlogic_or_result;
        default: bwlogic_result = bwlogic_xor_result;
        endcase
    end

                /////////////////////////////
                // Single-bit Instructions //
                /////////////////////////////

    logic [WIDTH-1:0] singlebit_result;

    always_comb begin
        unique case (operation_type_i)
            ALU_BCLR: singlebit_result = operand_a_i & ~shifter_result;
            ALU_BSET: singlebit_result = operand_a_i | shifter_result;
            ALU_BINV: singlebit_result = operand_a_i ^ shifter_result;
            default: singlebit_result = {{WIDTH-1{1'b0}}, shifter_result[0]};
        endcase
    end

                //////////////////
                // Bit Counting //
                //////////////////

    logic                   bitcount_32_bit_mode;
    bitcount_type_e         bitcount_zeros_op_type;
    logic [WIDTH-1:0]       bitcount_ones_result;
    logic [WIDTH-1:0]       bitcount_zeros_result;
    logic [WIDTH-1:0]       bitcount_result;

    always_comb begin
        unique case (operation_type_i)
            ALU_CLZW,
            ALU_CPOPW,
            ALU_CTZW: bitcount_32_bit_mode = 1'b1;
            default: bitcount_32_bit_mode = 1'b0;
        endcase

        unique case (operation_type_i)
            ALU_CTZ, ALU_CTZW: bitcount_zeros_op_type = BITCOUNT_TRAIL;
            default: bitcount_zeros_op_type = BITCOUNT_LEAD;
        endcase
    end

    zeroscounter zeros (
                    .operand_i(operand_a_i), 
                    .oper_type_i(bitcount_zeros_op_type), 
                    .is_32_bit_mode_i(bitcount_32_bit_mode), 
                    .result_o(bitcount_zeros_result));

    bitcounter ones (
                    .operand_i(operand_a_i), 
                    .is_32_bit_mode_i(bitcount_32_bit_mode), 
                    .result_o(bitcount_ones_result));

    always_comb begin
        unique case (operation_type_i)

            ALU_CLZ, ALU_CLZW,
            ALU_CTZ, ALU_CTZW: bitcount_result = {{WIDTH-$clog2(WIDTH)-1{1'b0}}, bitcount_zeros_result[$clog2(WIDTH):0]};

            default: bitcount_result = {{WIDTH-$clog2(WIDTH)-1{1'b0}}, bitcount_ones_result[$clog2(WIDTH):0]}; //cpop

        endcase
    end

                /////////////
                // Min/Max //
                /////////////

    logic [WIDTH-1:0] minmax_result;

    assign minmax_result = cmp_result ? operand_a_i : operand_b_i;

                ///////////////////////////////
                // Carry-Less Multiplication //
                ///////////////////////////////

    logic [2*WIDTH-1:0] clmult_wide_result;
    logic [WIDTH-1:0]   clmult_result;

    clmult_karatsuba clmult (
                            .operand_a_i(operand_a_i), 
                            .operand_b_i(operand_b_i), 
                            .result_o(clmult_wide_result));

    always_comb begin
        unique case (operation_type_i)
            ALU_CLMULH: clmult_result = clmult_wide_result[2*WIDTH-1:WIDTH];
            ALU_CLMULR: clmult_result = clmult_wide_result[2*WIDTH-2:WIDTH-1];
            default: clmult_result = clmult_wide_result[WIDTH-1:0]; //clmul
        endcase
    end

                ////////////
                // Xperm4 //
                ////////////

    logic [WIDTH/4-1:0][3:0] xperm4_mask_bits;
    logic [WIDTH/4-1:0][3:0] xperm4_vector;
    logic [WIDTH/4-1:0][3:0] xperm4_result;
    genvar xperm4_i;

    assign xperm4_mask_bits = operand_b_i;
    assign xperm4_vector = operand_a_i;

    generate
        for (xperm4_i = 0; xperm4_i < WIDTH/4; xperm4_i = xperm4_i + 1) begin : byte_mux_xperm4
            assign xperm4_result[xperm4_i] = xperm4_vector[xperm4_mask_bits[xperm4_i][3:0]];
        end
    endgenerate

                ////////////
                // Xperm8 //
                ////////////

    logic [WIDTH/8-1:0][7:0] xperm8_mask_bits;
    logic [WIDTH/8-1:0][7:0] xperm8_vector;
    logic [WIDTH/8-1:0][7:0] xperm8_result;
    genvar xperm8_i;

    assign xperm8_mask_bits = operand_b_i;
    assign xperm8_vector = operand_a_i;

    generate
        for (xperm8_i = 0; xperm8_i < WIDTH/8; xperm8_i = xperm8_i + 1) begin : byte_mux_xperm8
            assign xperm8_result[xperm8_i] = (~| xperm8_mask_bits[xperm8_i][7:3]) ? xperm8_vector[xperm8_mask_bits[xperm8_i][2:0]] : 8'b0;
        end
    endgenerate

                ///////////////
                // Zip/Unzip //
                ///////////////

    logic [WIDTH-1:0] zip_result;
    logic [WIDTH-1:0] unzip_result;
    genvar zip_unzip_i;

    generate
        for (zip_unzip_i = 0; zip_unzip_i < WIDTH/2; zip_unzip_i = zip_unzip_i + 1) begin : zip_unzip_loop

            assign unzip_result[zip_unzip_i] = operand_a_i[2*zip_unzip_i];
            assign unzip_result[zip_unzip_i + WIDTH/2] = operand_a_i[2*zip_unzip_i+1];

            assign zip_result[2*zip_unzip_i] = operand_a_i[zip_unzip_i];
            assign zip_result[2*zip_unzip_i+1] = operand_a_i[zip_unzip_i + WIDTH/2];

        end
    endgenerate

                ///////////////
                // Sext/Zext //
                ///////////////

    logic [WIDTH-1:0] signextend_result;

    always_comb begin
        unique case (operation_type_i)
            ALU_SEXTB: signextend_result = {{WIDTH-8{operand_a_i[7]}}, operand_a_i[7:0]};
            ALU_SEXTH: signextend_result = {{WIDTH-16{operand_a_i[15]}}, operand_a_i[15:0]};
            default: signextend_result = {{WIDTH-16{1'b0}}, operand_a_i[15:0]}; //zext.h
        endcase
    end

                //////////
                // Pack //
                //////////

    logic [WIDTH-1:0] pack_result;

    always_comb begin
        unique case (operation_type_i)
            ALU_PACKH: pack_result = {{WIDTH-16{1'b0}}, operand_b_i[7:0], operand_a_i[7:0]};
            ALU_PACKW: pack_result = {{WIDTH-32{1'b0}}, operand_b_i[15:0], operand_a_i[15:0]};
            default: pack_result = {operand_b_i[WIDTH/2-1:0], operand_a_i[WIDTH/2-1:0]}; //pack
        endcase
    end

                ///////////
                // orc.b //
                ///////////

    logic [WIDTH-1:0] orcb_result;
    genvar orcb_i;

    generate
        for (orcb_i = 0; orcb_i < WIDTH/8; orcb_i = orcb_i + 1) begin : orcb_loop
            assign orcb_result[orcb_i*8+7:orcb_i*8] = {8{| operand_a_i[orcb_i*8+7:orcb_i*8]}};
        end
    endgenerate

                ///////////
                // brev8 //
                ///////////

    logic [WIDTH-1:0] brev8_result;
    genvar brev8_i;

    generate
        for (brev8_i = 0; brev8_i < WIDTH/8; brev8_i = brev8_i + 1) begin : brev8_loop
            reverse #(.SIZE(8)) brev8_reverse (
                                .operand_i(operand_a_i[brev8_i*8+7:brev8_i*8]), 
                                .result_o(brev8_result[brev8_i*8+7:brev8_i*8]));
        end
    endgenerate

                //////////
                // rev8 //
                //////////

    logic [WIDTH-1:0] rev8_result;
    genvar rev8_i;

    generate
        for (rev8_i = 0; rev8_i < WIDTH/8; rev8_i = rev8_i + 1) begin : rev8_loop
            assign rev8_result[WIDTH-1-8*rev8_i:WIDTH-8-8*rev8_i] = operand_a_i[rev8_i*8+7:rev8_i*8];
        end
    endgenerate

                ///////////////
                // Final mux //
                ///////////////

    always_comb begin
        unique case (operation_type_i)

            ALU_XOR, ALU_XORN,
            ALU_AND, ALU_ANDN,
            ALU_OR, ALU_ORN: result_o = bwlogic_result;

            ALU_ADD, ALU_SUB, ALU_ADDUW,
            ALU_SH1ADD, ALU_SH1ADDUW,
            ALU_SH2ADD, ALU_SH2ADDUW,
            ALU_SH3ADD, ALU_SH3ADDUW: result_o = adder_result;

            ALU_SLL, ALU_SLLW, ALU_SLLUW,
            ALU_SRL, ALU_SRLW,
            ALU_SRA, ALU_SRAW,
            ALU_ROL, ALU_ROLW,
            ALU_ROR, ALU_RORW: result_o = shifter_result;

            ALU_EQ,   ALU_NE,
            ALU_GE,   ALU_GEU,
            ALU_LT,   ALU_LTU,
            ALU_SLT,  ALU_SLTU: result_o = {{WIDTH-1{1'b0}}, cmp_result};

            ALU_MIN,  ALU_MAX,
            ALU_MINU, ALU_MAXU: result_o = minmax_result;

            ALU_BSET, ALU_BCLR,
            ALU_BINV, ALU_BEXT: result_o = singlebit_result;

            ALU_CTZ, ALU_CTZW,
            ALU_CPOP, ALU_CPOPW,
            ALU_CLZ, ALU_CLZW: result_o = bitcount_result;

            ALU_ORCB: result_o = orcb_result;

            ALU_PACK, ALU_PACKH, ALU_PACKW: result_o = pack_result;

            ALU_ZEXTH, ALU_SEXTH, ALU_SEXTB: result_o = signextend_result;

            ALU_REV8: result_o = rev8_result;

            ALU_BREV8: result_o = brev8_result;

            ALU_XPERM4: result_o = xperm4_result;

            ALU_XPERM8: result_o = xperm8_result;

            ALU_ZIP: result_o = zip_result;
            ALU_UNZIP: result_o = unzip_result;

            ALU_CLMUL, ALU_CLMULH, ALU_CLMULR: result_o = clmult_result;

            default:;

        endcase
    end

endmodule

/*
module bitextender
    #(parameter WIDTH = 64)
    (
    input   logic [WIDTH-1:0] a,
    input   logic [2:0]       operation,
    input   logic             sign_ext,
    output  logic [WIDTH-1:0] result
);

    typedef enum logic {B_TYPE, S_TYPE, I_TYPE, J_TYPE, U_TYPE} operation_t;

    logic [WIDTH-1:0] temp_res;

    always_comb begin
        case (operation)
            B_TYPE: temp_res = {{WIDTH-13{a[12]}}, a[31], a[7], a[30:25], a[11:8], 1'b0};
            S_TYPE: temp_res = {{WIDTH-12{a[11]}}, a[31:25], a[11:7]};
            I_TYPE: temp_res = {{WIDTH-12{a[31]}}, a[31:20]};
            J_TYPE: temp_res = {{WIDTH-21{a[31]}}, a[31], a[19:12], a[20], a[30:21], 1'b0};
            U_TYPE: temp_res = {{WIDTH/2{a[31]}}, a[31:12], 12'b0};
        endcase
    end

    assign result = temp_res;

endmodule
*/