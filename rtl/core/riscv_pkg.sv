package riscv_pkg;

    localparam int WIDTH = 64;
    localparam int REG_ADDR_W = 5;

    typedef enum logic [6:0] {
        OPCODE_LOAD      = 7'b0000011,
        OPCODE_STORE     = 7'b0100011,
        OPCODE_BRANCH    = 7'b1100011,
        OPCODE_SYSTEM    = 7'b1110011,
        OPCODE_FENCE     = 7'b0001111,

        OPCODE_JAL       = 7'b1101111,
        OPCODE_JALR      = 7'b1100111,
        OPCODE_LUI       = 7'b0110111,
        OPCODE_AUIPC     = 7'b0010111,

        OPCODE_OP_32     = 7'b0111011,
        OPCODE_OP_64     = 7'b0110011,
        OPCODE_OP_IMM_32 = 7'b0011011,
        OPCODE_OP_IMM_64 = 7'b0010011
    } opcode_e;

    typedef enum logic [5:0] { //59

        //Arithmetic. 
        ALU_ADD,
        ALU_SUB,

        //Logical. 
        ALU_AND,
        ALU_OR,
        ALU_XOR,
        ALU_ANDN,
        ALU_ORN,
        ALU_XORN,

        //Shifts. 
        ALU_SLL,
        ALU_SRL,
        ALU_SRA,
        ALU_SLLW,
        ALU_SRLW,
        ALU_SRAW,
        ALU_SLLUW,
        ALU_ROL,
        ALU_ROR,
        ALU_ROLW,
        ALU_RORW,

        //Set less than. 
        ALU_SLT,
        ALU_SLTU,

        //Comparisons. 
        ALU_EQ,
        ALU_NE,
        ALU_LT,
        ALU_GE,
        ALU_LTU,
        ALU_GEU,

        //Min, Max from Bit ext.
        ALU_MAX,
        ALU_MIN,
        ALU_MAXU,
        ALU_MINU,

        //Shift and add from Bit ext.
        ALU_SH1ADD,
        ALU_SH2ADD,
        ALU_SH3ADD,

        //Bit-manipulation.
        ALU_BCLR,
        ALU_BEXT,
        ALU_BINV,
        ALU_BSET,

        //Bit counting.
        ALU_CLZ,
        ALU_CTZ,
        ALU_CPOP,
        ALU_CLZW,
        ALU_CTZW,
        ALU_CPOPW,

        ALU_ORCB,

        ALU_PACK,
        ALU_PACKH,
        ALU_PACKW,

        ALU_REV8,
        ALU_BREV8,

        ALU_SEXTB,
        ALU_SEXTH,
        ALU_ZEXTH,

        ALU_XPERM4,
        ALU_XPERM8,

        ALU_ZIP,
        ALU_UNZIP

        ALU_CLMUL,
        ALU_CLMULH,
        ALU_CLMULR

    } op_alu_e;

endpackage