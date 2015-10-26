BIN = interpreter \
      compiler-x86 compiler-x64 compiler-arm \
      jit-arm

CROSS_COMPILE = arm-linux-gnueabihf-
QEMU_ARM = qemu-arm -L /usr/arm-linux-gnueabihf
LUA = lua
PERF_stat = cycles,instructions,cache-misses
all: $(BIN)

CFLAGS = -Wall -std=gnu99 -I. -g

interpreter: interpreter.c
	$(CC) $(CFLAGS) -o $@ $^

compiler-x86: compiler-x86.c
	$(CC) $(CFLAGS) -o $@ $^

compiler-x64: compiler-x64.c
	$(CC) $(CFLAGS) -o $@ $^

compiler-arm: compiler-arm.c
	$(CC) $(CFLAGS) -o $@ $^

run-compiler: compiler-x86 compiler-arm
	./compiler-x86 progs/hello.b > hello.s
	$(CC) -m32 -o hello-x86 hello.s
	@echo 'x86: ' `./hello-x86`
	@echo
	#./compiler-x64 progs/hello.b > hello.s
	#$(CC) -o hello-x64 hello.s
	#@echo 'x64: ' `./hello-x64`
	#@echo
	./compiler-arm progs/hello.b > hello.s
	$(CROSS_COMPILE)gcc -o hello-arm hello.s
	@echo 'arm: ' `$(QEMU_ARM) hello-arm`
	@echo

jit0-x64: tests/jit0-x64.c
	$(CC) $(CFLAGS) -o $@ $^

jit-x64: dynasm-driver.c jit-x64.h
	$(CC) $(CFLAGS) -o $@ -DJIT=\"jit-x64.h\" \
		dynasm-driver.c
jit-x64.h: jit-x64.dasc
	        $(LUA) dynasm/dynasm.lua -o $@ jit-x64.dasc
run-jit-x64: jit-x64
	./jit-x64 progs/hello.b && objdump -D -b binary \
		-mi386 -Mx86-64 /tmp/jitcode

jit0-arm: tests/jit0-arm.c
	$(CROSS_COMPILE)gcc $(CFLAGS) -o $@ $^

jit-arm: dynasm-driver.c jit-arm.h
	$(CROSS_COMPILE)gcc $(CFLAGS) -DOPT -o $@ -DJIT=\"jit-arm.h\" \
		dynasm-driver.c
jit-arm.h: jit-arm.dasc
	$(LUA) dynasm/dynasm.lua -o $@ jit-arm.dasc
run-jit-arm: jit-arm
	$(QEMU_ARM) jit-arm progs/hanoi.b && \
	$(CROSS_COMPILE)objdump -D -b binary -marm /tmp/jitcode

bench-jit-x64: jit-x64
	@echo
	@echo Executing Brainf*ck benchmark suite. Be patient.
	@echo
	@env PATH='.:${PATH}' BF_RUN='$<' tests/bench.py

test: test_stack jit0-x64 jit0-arm
	./test_stack
	(./jit0-x64 42 ; echo $$?)
	($(QEMU_ARM) jit0-arm 42 ; echo $$?)

test_stack: tests/test_stack.c
	$(CC) $(CFLAGS) -o $@ $^

run-arm:
	for n in `seq 1 200` ;do\
	    $(QEMU_ARM) jit-arm progs/hanoi.b ;\
	done;
perf-stat:
	@sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
	@sudo sh -c "echo 1 > /proc/sys/vm/drop_caches"
	perf stat -r 1 -e $(PERF_stat) ./interpreter ./progs/hanoi.b

clean:
	$(RM) $(BIN) \
	      hello-x86 hello-x64 hello-arm hello.s \
	      test_stack jit0-x64 jit0-arm \
	      jit-x64.h jit-arm.h
