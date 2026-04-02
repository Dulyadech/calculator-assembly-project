; ======================================================================================
; Author :
;   1. Natthanicha Khodphan 67304385-3
;   2. Dulyadech Phuangchampee 673040387-9
;   3. Anchisa Hankate 673040639-8
; calc.s  —  Four-operation integer calculator for x86-64 Linux
;
; PURPOSE:
;   A pedagogical example of a CLI calculator. Demonstrates string parsing,
;   unsigned integer arithmetic, Linux syscalls, and ASCII/Integer conversion.
;
; COMPILATION:
;   Assembler: yasm -f elf64 calc.s -o calc.o
;   Linker:    ld -o calc calc.o
; ======================================================================================

section .data
    ; Prompt and Label Strings
    msg_prompt          db  "Enter statement: "
    msg_prompt_len      equ $ - msg_prompt      ; Calculate length: Current address ($) minus msg_prompt address

    msg_result          db  "Result: "
    msg_result_len      equ $ - msg_result

    msg_done            db  "Done.", 0x0A       ; 0x0A = Newline (\n)
    msg_done_len        equ $ - msg_done

    ; ---- Error Messages --------------------------------------------------------------
    ; These provide specific feedback for validation failures
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

    nl                  db  0x0A                ; Reusable newline character
    MAX_OPERAND         equ 9999                ; Constant for range validation

section .bss
    inbuf   resb 32     ; Reserve 32 bytes for raw user input string
    outbuf  resb 16     ; Reserve 16 bytes for converted ASCII output

section .text
    global  _start      ; Entry point for the linker (ld)

; ======================================================================================
; REGISTER CONVENTION (Architecture specific)
;   r12 = operand1        (Callee-saved: preserved across function calls)
;   r13 = operator char   (Stored as ASCII value)
;   r14 = operand2        (Callee-saved)
;   r15 = cursor snapshot (Used to track if rsi advanced during parsing)
;   rsi = parse cursor    (Pointer to the current character being processed in inbuf)
; ======================================================================================

_start:

    ; ----------------------------------------------------------------------------------
    ; 1. PROMPT: Display "Enter statement: "
    ; ----------------------------------------------------------------------------------
    mov     rax, 1              ; Syscall: sys_write
    mov     rdi, 1              ; File Descriptor: 1 (stdout)
    lea     rsi, [rel msg_prompt] ; Load effective address of string into rsi
    mov     rdx, msg_prompt_len ; Number of bytes to write
    syscall                     ; Invoke kernel

    ; ----------------------------------------------------------------------------------
    ; 2. READ: Get user input from keyboard
    ; ----------------------------------------------------------------------------------
    mov     rax, 0              ; Syscall: sys_read
    mov     rdi, 0              ; File Descriptor: 0 (stdin)
    lea     rsi, [rel inbuf]    ; Buffer address to store input
    mov     rdx, 32             ; Max bytes to read
    syscall                     ; Execution pauses here for user input

    ; ----------------------------------------------------------------------------------
    ; 3. INIT cursor
    ; ----------------------------------------------------------------------------------
    lea     rsi, [rel inbuf]    ; Initialize rsi as our global string pointer

    ; ----------------------------------------------------------------------------------
    ; 4. PARSE & VALIDATE  OPERAND 1
    ; ----------------------------------------------------------------------------------
    call    skip_spaces         ; Advance rsi past any leading spaces

    ; Check for '-' sign: Our logic only handles unsigned input strings
    cmp     byte [rsi], '-'
    je      err_neg_operand

    mov     r15, rsi            ; Save current pointer to check for progress later
    call    parse_int           ; Convert ASCII digits to integer in rax

    cmp     rsi, r15            ; If rsi didn't move, no digits were found
    je      err_no_digit

    cmp     rax, MAX_OPERAND    ; Business logic: Check if value > 9999
    ja      err_range

    mov     r12, rax            ; Store validated operand1 in r12

    ; ----------------------------------------------------------------------------------
    ; 5. PARSE & VALIDATE  OPERATOR
    ; ----------------------------------------------------------------------------------
    call    skip_spaces

    movzx   r13, byte [rsi]     ; Move byte into register and zero-extend
    inc     rsi                 ; Consume the operator character

    ; Validate operator is one of: + - * /
    cmp     r13b, '+'
    je      .op_ok
    cmp     r13b, '-'
    je      .op_ok
    cmp     r13b, '*'
    je      .op_ok
    cmp     r13b, '/'
    je      .op_ok
    jmp     err_invalid_op      ; Fallthrough: Not a valid operator
.op_ok:

    ; ----------------------------------------------------------------------------------
    ; 6. PARSE & VALIDATE  OPERAND 2
    ; ----------------------------------------------------------------------------------
    call    skip_spaces

    cmp     byte [rsi], '-'     ; Reject negative sign prefix
    je      err_neg_operand

    mov     r15, rsi            ; Snapshot pointer
    call    parse_int

    cmp     rsi, r15            ; Ensure digits were actually processed
    je      err_no_digit

    cmp     rax, MAX_OPERAND    ; Range check
    ja      err_range

    mov     r14, rax            ; Store validated operand2 in r14

    ; ----------------------------------------------------------------------------------
    ; 7. DIVIDE-BY-ZERO CHECK (Safety)
    ; ----------------------------------------------------------------------------------
    cmp     r13b, '/'           ; Is the operator division?
    jne     .no_divcheck
    cmp     r14, 0              ; Is divisor zero?
    je      err_div_zero
.no_divcheck:

    ; ----------------------------------------------------------------------------------
    ; 8. COMPUTE: Branch based on operator char stored in r13b
    ; ----------------------------------------------------------------------------------
    mov     rax, r12            ; Load operand1 into accumulator (rax)

    cmp     r13b, '+'
    je      do_add
    cmp     r13b, '-'
    je      do_sub
    cmp     r13b, '*'
    je      do_mul
    cmp     r13b, '/'
    je      do_div

do_add:
    add     rax, r14            ; rax = rax + r14
    jmp     print_result

do_sub:
    ; Logic: Because we handle unsigned numbers, (5 - 10) would wrap to a massive
    ; positive number. We prevent this by checking 'Below' (jb) for unsigned comparison.
    cmp     r12, r14
    jb      err_neg_result      ; If op1 < op2, result would be negative
    sub     rax, r14
    jmp     print_result

do_mul:
    imul    rax, r14            ; rax = rax * r14
    jmp     print_result

do_div:
    xor     rdx, rdx            ; CRITICAL: 'div' uses rdx:rax as the 128-bit dividend.
                                ; We must clear rdx to avoid Floating Point Exceptions.
    div     r14                 ; rax = (rdx:rax) / r14. Remainder goes to rdx.
    jmp     print_result

; ======================================================================================
; PRINT RESULT: Outputs the calculated integer back to the user
; ======================================================================================
print_result:
    push    rax                 ; Save result on stack before syscalls destroy rax

    ; Print "Result: " prefix
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_result]
    mov     rdx, msg_result_len
    syscall

    pop     rax                 ; Restore the calculated value into rax

    call    int_to_str          ; Convert binary rax into ASCII string in outbuf

    ; print the ASCII number (int_to_str returns start in rsi and length in rdx)
    mov     rax, 1
    mov     rdi, 1
    syscall

    ; Print final newline
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel nl]
    mov     rdx, 1
    syscall

print_done:
    ; Standard success exit block
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_done]
    mov     rdx, msg_done_len
    syscall

    mov     rax, 60             ; Syscall: sys_exit
    xor     rdi, rdi            ; Exit code: 0 (Success)
    syscall

; ======================================================================================
; ERROR HANDLERS: Common exit point for failures
; ======================================================================================

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

err_neg_operand:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_neg_operand]
    mov     rdx, msg_err_neg_operand_len
    syscall
    jmp     exit_error

err_neg_result:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel msg_err_neg_result]
    mov     rdx, msg_err_neg_result_len
    syscall
    jmp     exit_error

exit_error:
    mov     rax, 60             ; Syscall: sys_exit
    mov     rdi, 1              ; Exit code: 1 (General Error)
    syscall

; ======================================================================================
; SUBROUTINE: skip_spaces
;   Input:  rsi = pointer to string
;   Output: rsi = pointer to first non-space character
; ======================================================================================
skip_spaces:
    cmp     byte [rsi], ' '     ; Compare current char to ASCII space
    jne     .done               ; If not space, we are finished
    inc     rsi                 ; Else, move to next byte
    jmp     skip_spaces         ; Loop
.done:
    ret                         ; Return to caller

; ======================================================================================
; SUBROUTINE: parse_int (ASCII to Integer)
;   Logic:  result = (result * 10) + (char - '0')
;   Input:  rsi = pointer to start of digits
;   Output: rax = the resulting integer
;           rsi = first non-digit char
; ======================================================================================
parse_int:
    xor     rax, rax            ; Clear accumulator (result = 0)
.loop:
    movzx   rcx, byte [rsi]     ; Get current character
    cmp     cl, '0'             ; Check if < '0'
    jb      .done
    cmp     cl, '9'             ; Check if > '9'
    ja      .done

    sub     cl, '0'             ; Convert ASCII ('0'=48) to raw value (0)
    imul    rax, rax, 10        ; result *= 10 (shift decimal place)
    add     rax, rcx            ; result += digit
    inc     rsi                 ; Advance pointer
    jmp     .loop
.done:
    ret

; ======================================================================================
; SUBROUTINE: int_to_str (Integer to ASCII)
;   Logic:  Extract digits by dividing by 10. Store digits from right-to-left.
;   Input:  rax = binary integer
;   Output: rsi = pointer to start of string (in outbuf)
;           rdx = number of digits
; ======================================================================================
int_to_str:
    lea     rcx, [rel outbuf + 14] ; Point to the end of our buffer (working backwards)
    xor     r10, r10            ; r10 = digit counter

    test    rax, rax            ; Check if rax is 0
    jnz     .divide_loop
    mov     byte [rcx], '0'     ; Handle edge case: value is 0
    mov     rsi, rcx
    mov     rdx, 1
    ret

.divide_loop:
    test    rax, rax            ; Check if any digits remain
    jz      .finish
    xor     rdx, rdx            ; Clear rdx for div
    mov     r9, 10
    div     r9                  ; rax = quotient, rdx = remainder (the digit)
    add     dl, '0'             ; Convert raw digit to ASCII
    mov     [rcx], dl           ; Store character in buffer
    dec     rcx                 ; Move buffer pointer backwards
    inc     r10                 ; Increment count
    jmp     .divide_loop

.finish:
    inc     rcx                 ; Adjust pointer (rcx points one before the first digit)
    mov     rsi, rcx            ; Return pointer in rsi for sys_write
    mov     rdx, r10            ; Return count in rdx for sys_write
    ret
