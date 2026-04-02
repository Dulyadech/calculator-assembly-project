; ================================================================
; calc.asm  —  Four-operation integer calculator
;
; Platform : x86-64 Linux, ELF64
; Assembler: YASM  (yasm -f elf64)
; Linker   : ld    (ld -o calc calc.o)
;
; Syscalls used:
;   0  = read   (fd=0, buf, count) → rax = bytes read
;   1  = write  (fd=1, buf, count) → rax = bytes written
;  60  = exit   (code)
;
; Input  (stdin) : <op1> <operator> <op2>   spaces optional
; Output (stdout): decimal result + newline
;
; Examples:
;   705 + 213   →  918
;   9999 - 9998 →  1
;   123 * 45    →  5535
;   9876 / 543  →  18
;   12+34       →  46
;   1000 / 10   →  100
; ================================================================

section .data
    nl      db  0x0A            ; newline character (output only)

section .bss
    inbuf   resb 32             ; raw input buffer  (expression line)
    outbuf  resb 16             ; digit-conversion workspace

section .text
    global  _start

; ================================================================
; ENTRY POINT
; ================================================================
_start:

    ; ----------------------------------------------------------
    ; 1. READ: read one expression line from stdin
    ;    syscall: read(fd=0, buf=inbuf, count=32)
    ; ----------------------------------------------------------
    mov     rax, 0              ; SYS_read
    mov     rdi, 0              ; fd = 0 (stdin)
    lea     rsi, [rel inbuf]    ; destination buffer
    mov     rdx, 32             ; max bytes to read
    syscall                     ; rax = bytes actually read (unused)

    ; ----------------------------------------------------------
    ; 2. INIT: point parse cursor at start of input buffer
    ; ----------------------------------------------------------
    lea     rsi, [rel inbuf]    ; rsi = parse cursor

    ; ----------------------------------------------------------
    ; 3. PARSE OPERAND 1
    ; ----------------------------------------------------------
    call    skip_spaces         ; skip any leading spaces
    call    parse_int           ; rax = first integer
    mov     r12, rax            ; r12 = operand1 (preserved)

    ; ----------------------------------------------------------
    ; 4. PARSE OPERATOR
    ; ----------------------------------------------------------
    call    skip_spaces         ; skip spaces before operator
    movzx   r13, byte [rsi]     ; r13 = operator character (zero-extended)
    inc     rsi                 ; consume the operator character

    ; ----------------------------------------------------------
    ; 5. PARSE OPERAND 2
    ; ----------------------------------------------------------
    call    skip_spaces         ; skip spaces after operator
    call    parse_int           ; rax = second integer
    mov     r14, rax            ; r14 = operand2 (preserved)

    ; ----------------------------------------------------------
    ; 6. COMPUTE: dispatch based on operator character
    ; ----------------------------------------------------------
    mov     rax, r12            ; rax = operand1 (result accumulator)

    cmp     r13, '+'
    je      do_add
    cmp     r13, '-'
    je      do_sub
    cmp     r13, '*'
    je      do_mul
    cmp     r13, '/'
    je      do_div
    jmp     exit_prog           ; unknown operator → clean exit

do_add:
    add     rax, r14            ; rax = operand1 + operand2
    jmp     print_result

do_sub:
    sub     rax, r14            ; rax = operand1 - operand2
    jmp     print_result

do_mul:
    imul    rax, r14            ; rax = operand1 * operand2
    jmp     print_result

do_div:
    xor     rdx, rdx            ; zero-extend: rdx:rax = operand1
    div     r14                 ; rax = quotient, rdx = remainder (discarded)
    jmp     print_result

    ; ----------------------------------------------------------
    ; 7. OUTPUT: convert rax to ASCII, write to stdout
    ; ----------------------------------------------------------
print_result:
    call    int_to_str          ; → rsi = ptr to first digit
                                ;   → rdx = byte count

    mov     rax, 1              ; SYS_write
    mov     rdi, 1              ; fd = 1 (stdout)
    syscall                     ; write the result digits

    ; write the trailing newline
    mov     rax, 1              ; SYS_write
    mov     rdi, 1              ; stdout
    lea     rsi, [rel nl]       ; address of newline byte
    mov     rdx, 1              ; 1 byte
    syscall

exit_prog:
    mov     rax, 60             ; SYS_exit
    xor     rdi, rdi            ; exit code 0
    syscall


; ================================================================
; skip_spaces
;   Skip over ASCII space characters (0x20) at [rsi].
;   Stops at the first non-space character (does NOT consume it).
;
;   Modifies : rsi  (advanced past spaces)
;   Preserves: all other registers
; ================================================================
skip_spaces:
    cmp     byte [rsi], ' '     ; is current char a space?
    jne     .done               ; no  → stop
    inc     rsi                 ; yes → advance cursor
    jmp     skip_spaces         ; check next character
.done:
    ret


; ================================================================
; parse_int
;   Parse an unsigned decimal integer from the string at [rsi].
;   Reads digit characters ('0'–'9') until a non-digit is found.
;   Leaves rsi pointing at the first non-digit character.
;
;   Algorithm: accumulator = accumulator * 10 + digit_value
;
;   Returns  : rax = parsed integer value
;   Modifies : rax, rcx, rsi
;   Preserves: all other registers
; ================================================================
parse_int:
    xor     rax, rax            ; accumulator = 0
.loop:
    movzx   rcx, byte [rsi]     ; rcx = current character (zero-extended)
    cmp     cl, '0'
    jb      .done               ; below '0' → not a digit, stop
    cmp     cl, '9'
    ja      .done               ; above '9' → not a digit, stop
    sub     cl, '0'             ; convert ASCII '0'-'9' to value 0-9
    imul    rax, rax, 10        ; shift accumulator left one decimal place
    add     rax, rcx            ; add new digit
    inc     rsi                 ; advance past this digit
    jmp     .loop
.done:
    ret


; ================================================================
; int_to_str
;   Convert an unsigned 64-bit integer in rax to a decimal ASCII
;   string stored in outbuf.
;
;   Strategy: repeatedly divide by 10, collect remainders as digits
;   (they arrive in reverse order), then return a pointer to the
;   first stored digit.
;
;   The digits are written RIGHT-TO-LEFT starting at outbuf[14],
;   so the lowest digit lands at outbuf[14], the tens digit at
;   outbuf[13], and so on.  After the loop, rcx+1 points to the
;   most-significant digit.
;
;   Returns  : rsi = pointer to first (leftmost) digit in outbuf
;              rdx = number of characters in the result string
;   Modifies : rcx, rdx, r9, r10
;   Preserves: rax, r12, r13, r14
; ================================================================
int_to_str:
    lea     rcx, [rel outbuf + 14]  ; write cursor at outbuf[14] (rightmost)
    xor     r10, r10                ; character count = 0

    ; ---- Special case: value is zero ----------------------------
    test    rax, rax
    jnz     .divide_loop
    mov     byte [rcx], '0'         ; store single '0'
    mov     rsi, rcx                ; point rsi at it
    mov     rdx, 1                  ; length = 1
    ret

    ; ---- General case: divide by 10 repeatedly ------------------
.divide_loop:
    test    rax, rax                ; done when quotient reaches 0
    jz      .finish
    xor     rdx, rdx                ; zero-extend: rdx:rax = current value
    mov     r9, 10
    div     r9                      ; rax = quotient, rdx = remainder (0-9)
    add     dl, '0'                 ; remainder → ASCII digit character
    mov     [rcx], dl               ; store digit at current cursor position
    dec     rcx                     ; move cursor left (toward lower addresses)
    inc     r10                     ; increment digit count
    jmp     .divide_loop

.finish:
    inc     rcx                     ; cursor overshot by 1: move back right
    mov     rsi, rcx                ; rsi = pointer to leftmost digit
    mov     rdx, r10                ; rdx = total digit count
    ret