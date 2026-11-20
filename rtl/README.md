# Synthesizable RTL Architecture (SystemVerilog)

This directory contains the complete synthesizable SystemVerilog source code for the AXI4 Task-Aware Object Selection Hardware Accelerator IP core.

## Module Directory

| Module File | Functional Description | Key Microarchitectural Features |
| :--- | :--- | :--- |
| **`accelerator_top.sv`** | Top-Level IP Subsystem | Integrates AXI4 master DMA, AXI4-Lite slave, compute pipeline, and interrupt controller. |
| **`affordance_scoring_engine.sv`** | Vector Dot-Product Engine | 3-stage pipelined signed Q1.15 DSP48E1 multiplier evaluating $S_{\text{sem}} = \sum v_{\text{task}}[k] \times v_{\text{obj}}[k]$. |
| **`context_reasoning_engine.sv`** | Semantic Context Reweighter | Evaluates 2-bit domain prior tags: `PREFERRED` (+0.15 bonus), `PENALISED` (0.05× attenuation), `NEVER_TOOL` (force 0). |
| **`rejection_gate.sv`** | Parallel Threshold Gate | Parallel comparator array pruning non-viable objects below dynamic task threshold $\tau_{\text{task}}$. |
| **`topk_selector.sv`** | Tournament Reduction Tree | **5-stage parallel balanced tournament tree ($O(\log_2 N)$)** sorting 32 candidates down to 1 winner in **4.5 ns** (5 logic levels). |
| **`axi_master_if.sv`** | 64-bit Master DMA Engine | Autonomous AXI4 master burst generator streaming 64-bit vector beats from external memory without host CPU intervention. |
| **`axi_slave_if.sv`** | AXI4-Lite Slave Register File | 32-bit memory-mapped control/status register (MMIO) interface responding at base address `0x20060000`. |
| **`controller_fsm.sv`** | Master State Sequencer | Coordinates DMA burst ingestion, pipeline synchronization, tournament triggering, and completion interrupts. |
| **`input_buffer.sv`** | Synchronous Input Memory | $1024 \times 64$-bit dual-port synchronous buffer (RAMB36E1) holding candidate embeddings and context tags. |
| **`output_buffer.sv`** | Result Ingestion Buffer | Dual-port output packet packer stamping header magic `0x44564330` with winner ID and affordance score. |
