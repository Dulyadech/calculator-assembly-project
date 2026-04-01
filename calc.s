; ================================================================
; calc.asm  —  Four-operation integer calculator
;
; Platform : x86-64 Linux, ELF64
; Assembler: YASM  (yasm -f elf64)
; Linker   : ld    (ld -o calc calc.o)
;
; Syscalls used:
;   0  = read
;   1  = write
;  60  = exit
;
; Input  (stdin) : <op1> <operator> <op2>   spaces optional
; Output (stdout): prompt, result line, done message
; ================================================================

section .data

    ; ---- output messages ----------------------------------------
    msg_prompt      db  "Enter statement: "
    msg_prompt_len  equ $ - msg_prompt          ; 18 bytes

    msg_result      db  "Result: "
    msg_result_len  equ $ - msg_result          ; 8 bytes

    msg_done        db  "Done.", 0x0A
    msg_done_len    equ $ - msg_done            ; 6 bytes

    nl              db  0x0A                    ; standalone newline

section .bss
    inbuf   resb 32             ; raw input buffer
    outbuf  resb 16             ; digit-conversion workspace

section .text
    global  _start

; ================================================================
; ENTRY POINT
; ================================================================
_start:

    ; ----------------------------------------------------------
    ; 1. PROMPT: print "Enter statement: "
    ; ----------------------------------------------------------
    mov     rax, 1                      ; SYS_write
    mov     rdi, 1                      ; stdout
    lea     rsi, [rel msg_prompt]
    mov     rdx, msg_prompt_len
    syscall

    ; ----------------------------------------------------------
    ; 2. READ: read one expression line from stdin
    ; ----------------------------------------------------------
    mov     rax, 0                      ; SYS_read
    mov     rdi, 0                      ; stdin
    lea     rsi, [rel inbuf]
    mov     rdx, 32
    syscall

    ; ----------------------------------------------------------
    ; 3. INIT: point parse cursor at start of input buffer
    ; ----------------------------------------------------------
    lea     rsi, [rel inbuf]

    ; ----------------------------------------------------------
    ; 4. PARSE OPERAND 1
    ; ----------------------------------------------------------
    call    skip_spaces
    call    parse_int
    mov     r12, rax                    ; r12 = operand1

    ; ----------------------------------------------------------
    ; 5. PARSE OPERATOR
    ; ----------------------------------------------------------
    call    skip_spaces
    movzx   r13, byte [rsi]             ; r13 = operator character
    inc     rsi

    ; ----------------------------------------------------------
    ; 6. PARSE OPERAND 2
    ; ----------------------------------------------------------
    call    skip_spaces
    call    parse_int
    mov     r14, rax                    ; r14 = operand2

    ; ----------------------------------------------------------
    ; 7. COMPUTE: dispatch on operator
    ; ----------------------------------------------------------
    mov     rax, r12                    ; rax = operand1

    cmp     r13, '+'
    je      do_add
    cmp     r13, '-'
    je      do_sub
    cmp     r13, '*'
    je      do_mul
    cmp     r13, '/'
    je      do_div
    jmp     print_done                  ; unknown operator → skip to done

do_add:
    add     rax, r14
    jmp     print_result

do_sub:
    sub     rax, r14
    jmp     print_result

do_mul:
    imul    rax, r14
    jmp     print_result

do_div:
    xor     rdx, rdx
    div     r14                         ; rax = quotient
    jmp     print_result

    ; ----------------------------------------------------------
    ; 8. PRINT LABEL: "Result: "
    ; ----------------------------------------------------------
print_result:
    push    rax                         ; save computed result on stack

    mov     rax, 1                      ; SYS_write
    mov     rdi, 1                      ; stdout
    lea     rsi, [rel msg_result]
    mov     rdx, msg_result_len
    syscall

    pop     rax                         ; restore computed result

    ; ----------------------------------------------------------
    ; 9. PRINT DIGITS: convert rax → ASCII, write to stdout
    ; ----------------------------------------------------------
    call    int_to_str                  ; → rsi = digit ptr, rdx = length

    mov     rax, 1                      ; SYS_write
    mov     rdi, 1
    syscall                             ; write result digits

    ; write trailing newline after digits
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rel nl]
    mov     rdx, 1
    syscall

    ; ----------------------------------------------------------
    ; 10. PRINT: "Done."
    ; ----------------------------------------------------------
print_done:
    mov     rax, 1                      ; SYS_write
    mov     rdi, 1
    lea     rsi, [rel msg_done]
    mov     rdx, msg_done_len
    syscall

    ; ----------------------------------------------------------
    ; 11. EXIT
    ; ----------------------------------------------------------
exit_prog:
    mov     rax, 60                     ; SYS_exit
    xor     rdi, rdi                    ; exit code 0
    syscall


; ================================================================
; skip_spaces
;   Advance rsi past all ASCII space (0x20) characters.
;   Stops at first non-space without consuming it.
;   Modifies: rsi
; ================================================================
skip_spaces:
    cmp     byte [rsi], ' '
    jne     .done
    inc     rsi
    jmp     skip_spaces
.done:
    ret


; ================================================================
; parse_int
;   Parse decimal digits at [rsi] into an unsigned integer.
;   rsi is left pointing at the first non-digit character.
;   Returns: rax = integer value
;   Modifies: rax, rcx, rsi
; ================================================================
parse_int:
    xor     rax, rax                    ; accumulator = 0
.loop:
    movzx   rcx, byte [rsi]             ; rcx = current byte
    cmp     cl, '0'
    jb      .done
    cmp     cl, '9'
    ja      .done
    sub     cl, '0'                     ; ASCII → digit value
    imul    rax, rax, 10                ; shift accumulator
    add     rax, rcx                    ; add new digit
    inc     rsi
    jmp     .loop
.done:
    ret


; ================================================================
; int_to_str
;   Convert unsigned integer in rax to decimal ASCII in outbuf.
;   Digits written right-to-left starting at outbuf[14].
;   Returns: rsi = pointer to first digit
;            rdx = digit count
;   Modifies: rcx, rdx, r9, r10
;   Preserves: rax, r12, r13, r14
; ================================================================
int_to_str:
    lea     rcx, [rel outbuf + 14]      ; write cursor (rightmost position)
    xor     r10, r10                    ; digit count = 0

    test    rax, rax                    ; special case: value = 0
    jnz     .divide_loop
    mov     byte [rcx], '0'
    mov     rsi, rcx
    mov     rdx, 1
    ret

.divide_loop:
    test    rax, rax
    jz      .finish
    xor     rdx, rdx                    ; zero-extend for div
    mov     r9, 10
    div     r9                          ; rax = quotient, rdx = remainder
    add     dl, '0'                     ; remainder → ASCII
    mov     [rcx], dl
    dec     rcx
    inc     r10
    jmp     .divide_loop

.finish:
    inc     rcx                         ; correct one-position overshoot
    mov     rsi, rcx                    ; rsi → first (leftmost) digit
    mov     rdx, r10                    ; rdx = digit count
    ret