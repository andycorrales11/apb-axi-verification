# AMBA APB and AXI Verification Project

**GOAL**: Design and then verify a reusable UVM verification environment for AMBA bus protocols, and use a mutation-testing harness to plant known bugs into the DUT in order to check if bug catching really works.

**TOOLS** I will be using Verilator 5.048 with support for UVM. The UVM version I am using is 2020.3.1, as a pre flattened single-file amalgamation. This makes up for the lack of support for the uvm_core source tree. 

** SOURCES **
- *AMBA APB Protocol Specification* - Arm Ltd: https://developer.arm.com/documentation/ihi0024/latest/
