`timescale 1ns / 1ps

module DPFU(
    input  logic         clk,
    input  logic         rst_n,

    // Interface to Memory (128-bit Burst)
    output logic [31:0]  mem_addr,
    output logic         mem_req,
    output logic[2:0]   mem_count,
    input  logic [127:0] mem_rdata,
    input  logic         mem_rvalid,
    input  logic         mem_rdone,

    // Branch Resolution (From Execute Stage)
    input  logic         branch_resolved,
    input  logic         branch_taken,
    input  logic [31:0]  branch_pc,
    input  logic [31:0]  branch_target,

    // Decoder Interface
    input  logic         dec_read_en,
    output logic [31:0]  dec_instr,
    output logic [31:0]  dec_pc,
    output logic         dec_valid,
    
    output logic         flush_out
);

    // FSM States
    typedef enum logic { IDLE, WAIT_DATA } state_t;
    state_t state;

    // Internal signals
    logic [31:0] current_fpc;
    logic [31:0] next_fpc;
    logic [3:0]  fifo_count;
    logic        fifo_full, flush;
    logic        branch_mispredicted;
    
    // BPU Signals
    logic        pred_taken;
    logic        pred_valid;
    logic [31:0] pred_target;

    assign flush_out = flush;

    // =========================================================
    // 1. INTEGRATED MISPREDICTION LOGIC
    // =========================================================
    always_comb begin
        branch_mispredicted = 1'b0;
        flush = 1'b0;
        
        if (branch_resolved) begin
            if (pred_valid) begin
                // Case: Predicted but wrong direction OR wrong target
                if ((branch_taken != pred_taken) || 
                    (branch_taken && (branch_target != pred_target))) begin
                    branch_mispredicted = 1'b1;
                    flush = 1'b1;
                end
            end else if (branch_taken) begin
                // Case: Not predicted as a branch but it actually was
                branch_mispredicted = 1'b1;
                flush = 1'b1;
            end
        end
    end

    // =========================================================
    // 2. PC UPDATE LOGIC (Maintains 16-byte Burst)
    // =========================================================
    always_comb begin
        if (branch_mispredicted) begin
            next_fpc = branch_target;
        end else if (pred_valid && pred_taken) begin
            next_fpc = pred_target;
        end else begin
            // Maintain original Burst Step: 4 instructions = 16 bytes
            next_fpc = current_fpc + 3'd4;
        end
    end

//     =========================================================
//     3. FETCH CONTROLLER FSM (Burst Timing)
//     =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            state       <= IDLE;
            current_fpc <= (flush) ? branch_target : 32'h0;
            mem_req     <= 1'b0;
            mem_addr    <= 32'h0;
           
        end else begin
            case (state)
                IDLE: begin
                    // Request next 128-bit block if FIFO has space
                    if (!fifo_full) begin
                        mem_req   <= 1'b1;
                        mem_addr  <= current_fpc;
                        state     <= WAIT_DATA; 
                        mem_count <= 8-fifo_count;
                    end
                end

                WAIT_DATA: begin
                    mem_req <= 1'b0; 
                    if (mem_rdone) begin
                        // Transaction complete: Move to the pre-calculated next_fpc
                        current_fpc <= next_fpc;
                        state       <= IDLE;
                    end
                end
            endcase
        end
    end



    // =========================================================
    // 4. SUB-MODULES (BPU & FIFO)
    // =========================================================
    
    branch_predictor bp_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pc_in(current_fpc),
        .predict_enable(mem_req && (state == IDLE)),
        .prediction(pred_taken),
        .predicted_target(pred_target),
        .prediction_valid(pred_valid),
        .update_enable(branch_resolved),
        .update_pc(branch_pc),
        .update_taken(branch_taken),
        .update_target(branch_target)
    );

    fifo #(.DEPTH(8)) fifo_inst (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .write_enable(mem_rvalid),
        .write_data(mem_rdata),
        .write_pc(current_fpc),
        .ins_count(3'd4), // Burst writes 4 instructions at once
        .read_enable(dec_read_en),
        .read_data(dec_instr),
        .read_pc(dec_pc),
        .valid(dec_valid),
        .full(fifo_full),
        .count(fifo_count),
        .storetest()
    );

endmodule
