; ================================================================
; calc.asm  —  Four-operation integer calculator  (validated)
;
; Platform : x86-64 Linux, ELF64
; Assembler: YASM  (yasm -f elf64)
; Linker   : ld    (ld -o calc calc.o)
;
; Validations:
;   - Operands must be digits only (no leading minus sign)
;   - Each operand value must be in range 0 – 9999
;   - Operator must be one of  +  -  *  /
;   - Division by zero is rejected
;   - Subtraction result must not be negative (op1 >= op2)
; ================================================================

section .data

    msg_prompt          db  "Enter statement: "
    msg_prompt_len      equ $ - msg_prompt

    msg_result          db  "Result: "
    msg_result_len      equ $ - msg_result

    msg_done            db  "Done.", 0x0A
    msg_done_len        equ $ - msg_done

    ; ---- error messages -----------------------------------------
    msg_err_no_digit    db  "Error: invalid operand", 0x0A
    msg_err_no_digit_len equ $ - msg_err_no_digit

    msg_err_range       db  "Error: operand out of range (0-9999)", 0x0A
    msg_err_range_len   equ $ - msg_err_range

    msg_err_op          db  "Error: invalid operator", 0x0A
    msg_err_op_len      equ $ - msg_err_op

    msg_err_divzero     db  "Error: division by zero", 0x0A
    msg_err_divzero_len equ $ - msg_err_divzero

    msg_err_neg_operand     db  "Error: operand cannot be negative", 0x0A
    msg_err_neg_operand_len equ $ - msg_err_neg_operand

    msg_err_neg_result      db  "Error: result cannot be negative", 0x0A
    msg_err_neg_result_len  equ $ - msg_err_neg_result

    nl                  db  0x0A
    MAX_OPERAND         equ 9999

section .bss
    inbuf   resb 32
    outbuf  resb 16

section .text
    global  _start

; ================================================================
; REGISTER CONVENTION
;   r12 = operand1        (callee-saved)
;   r13 = operator char   (callee-saved)
;   r14 = operand2        (callee-saved)
;   r15 = cursor snapshot (callee-saved)
;   rsi = parse cursor
; ================================================================

_start:

    ; ----------------------------------------------------------
    ; 1. PROMPT
    ; ----------------------------------------------------------
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_prompt]
    mov     rdx, msg_prompt_len
    syscall

    ; ----------------------------------------------------------
    ; 2. READ
    ; ----------------------------------------------------------
    mov     rax, 0
    mov     rdi, 0
    lea     rsi, [rel inbuf]
    mov     rdx, 32
    syscall

    ; ----------------------------------------------------------
    ; 3. INIT cursor
    ; ----------------------------------------------------------
    lea     rsi, [rel inbuf]

    ; ----------------------------------------------------------
    ; 4. PARSE & VALIDATE  OPERAND 1
    ; ----------------------------------------------------------
    call    skip_spaces

    ; >>> NEW: reject leading minus sign on operand1
    cmp     byte [rsi], '-'
    je      err_neg_operand

    mov     r15, rsi                    ; snapshot cursor
    call    parse_int

    cmp     rsi, r15                    ; any digit consumed?
    je      err_no_digit

    cmp     rax, MAX_OPERAND            ; value <= 9999?
    ja      err_range

    mov     r12, rax                    ; r12 = operand1  ✓

    ; ----------------------------------------------------------
    ; 5. PARSE & VALIDATE  OPERATOR
    ; ----------------------------------------------------------
    call    skip_spaces

    movzx   r13, byte [rsi]
    inc     rsi

    cmp     r13b, '+'
    je      .op_ok
    cmp     r13b, '-'
    je      .op_ok
    cmp     r13b, '*'
    je      .op_ok
    cmp     r13b, '/'
    je      .op_ok
    jmp     err_invalid_op
.op_ok:

    ; ----------------------------------------------------------
    ; 6. PARSE & VALIDATE  OPERAND 2
    ; ----------------------------------------------------------
    call    skip_spaces

    ; >>> NEW: reject leading minus sign on operand2
    cmp     byte [rsi], '-'
    je      err_neg_operand

    mov     r15, rsi                    ; snapshot cursor
    call    parse_int

    cmp     rsi, r15                    ; any digit consumed?
    je      err_no_digit

    cmp     rax, MAX_OPERAND            ; value <= 9999?
    ja      err_range

    mov     r14, rax                    ; r14 = operand2  ✓

    ; ----------------------------------------------------------
    ; 7. DIVIDE-BY-ZERO CHECK
    ; ----------------------------------------------------------
    cmp     r13b, '/'
    jne     .no_divcheck
    cmp     r14, 0
    je      err_div_zero
.no_divcheck:

    ; ----------------------------------------------------------
    ; 8. COMPUTE
    ; ----------------------------------------------------------
    mov     rax, r12

    cmp     r13b, '+'
    je      do_add
    cmp     r13b, '-'
    je      do_sub
    cmp     r13b, '*'
    je      do_mul
    cmp     r13b, '/'
    je      do_div

do_add:
    add     rax, r14
    jmp     print_result

do_sub:
    ; >>> NEW: check operand1 >= operand2  before subtracting
    ;         both are unsigned integers in 0-9999
    ;         if op1 < op2 the result would be negative → reject
    cmp     r12, r14                    ; operand1 - operand2 < 0 ?
    jb      err_neg_result              ; unsigned below → result negative
    sub     rax, r14
    jmp     print_result

do_mul:
    imul    rax, r14
    jmp     print_result

do_div:
    xor     rdx, rdx
    div     r14
    jmp     print_result

; ================================================================
; PRINT RESULT
; ================================================================
print_result:
    push    rax

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_result]
    mov     rdx, msg_result_len
    syscall

    pop     rax

    call    int_to_str

    mov     rax, 1
    mov     rdi, 1
    syscall

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel nl]
    mov     rdx, 1
    syscall

print_done:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_done]
    mov     rdx, msg_done_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

; ================================================================
; ERROR HANDLERS
; ================================================================

err_no_digit:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_no_digit]
    mov     rdx, msg_err_no_digit_len
    syscall
    jmp     exit_error

err_range:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_range]
    mov     rdx, msg_err_range_len
    syscall
    jmp     exit_error

err_invalid_op:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_op]
    mov     rdx, msg_err_op_len
    syscall
    jmp     exit_error

err_div_zero:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_divzero]
    mov     rdx, msg_err_divzero_len
    syscall
    jmp     exit_error

; >>> NEW
err_neg_operand:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_neg_operand]
    mov     rdx, msg_err_neg_operand_len
    syscall
    jmp     exit_error

; >>> NEW
err_neg_result:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_neg_result]
    mov     rdx, msg_err_neg_result_len
    syscall
    jmp     exit_error

exit_error:
    mov     rax, 60
    mov     rdi, 1                      ; exit code 1 = error
    syscall

; ================================================================
; skip_spaces — advance rsi past space characters (0x20)
; ================================================================
skip_spaces:
    cmp     byte [rsi], ' '
    jne     .done
    inc     rsi
    jmp     skip_spaces
.done:
    ret

; ================================================================
; parse_int — read decimal digits at [rsi] → rax
;   rsi left at first non-digit
;   Modifies: rax, rcx, rsi
; ================================================================
parse_int:
    xor     rax, rax
.loop:
    movzx   rcx, byte [rsi]
    cmp     cl, '0'
    jb      .done
    cmp     cl, '9'
    ja      .done
    sub     cl, '0'
    imul    rax, rax, 10
    add     rax, rcx
    inc     rsi
    jmp     .loop
.done:
    ret

; ================================================================
; int_to_str — convert rax (unsigned) to decimal ASCII in outbuf
;   Returns: rsi = ptr to first digit,  rdx = char count
;   Modifies: rcx, rdx, r9, r10
;   Preserves: rax, r12, r13, r14, r15
; ================================================================
int_to_str:
    lea     rcx, [rel outbuf + 14]
    xor     r10, r10

    test    rax, rax
    jnz     .divide_loop
    mov     byte [rcx], '0'
    mov     rsi, rcx
    mov     rdx, 1
    ret

.divide_loop:
    test    rax, rax
    jz      .finish
    xor     rdx, rdx
    mov     r9, 10
    div     r9
    add     dl, '0'
    mov     [rcx], dl
    dec     rcx
    inc     r10
    jmp     .divide_loop

.finish:
    inc     rcx
    mov     rsi, rcx
    mov     rdx, r10
    ret