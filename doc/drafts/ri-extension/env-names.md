# IYI_* names in the tree (ri-extension, DRAFT 7.3)

Every `IYI_*` token in tracked files outside doc/archive and
doc/reference, as it stood before the rename (2113f8f24..9a4a4dc37).
One line each: class, name, first place it is read or defined.

Classes:

* user: an environment variable a person sets; renamed `RIS_X`.
  A set `IYI_X` with no `RIS_X` prints "IYI_X is not read: set
  RIS_X" (`Iyi::Config.notice_iyi_variables`).
* build: a build-time or compiler-source constant (Makefile
  variable, C macro guard, Crystal constant); kept.
* runtime: a constant of the runtime in src/ris/; kept.
* test data: a variable name a test program sets for its own child
  process and reads back; kept, no user sets it.
* prose: a placeholder in a document (`IYI_X`, `IYI_TL_`); kept.

Totals: user 34, build 41, runtime 68, test data 13, prose 1; 157 names.

* user: `IYI_AUTO_INLINE` src/compiler/iyi/codegen/auto_inline.cr:16
* user: `IYI_BINARY` test/cli/lsp_session.py:3432
* user: `IYI_CACHE_DIR` src/compiler/iyi/codegen/cache_dir.cr:209
* user: `IYI_DAEMON` src/compiler/iyi/command/daemon.cr:107
* user: `IYI_DAEMON_SOCKET` src/compiler/iyi/command/daemon.cr:52
* user: `IYI_DEBUG_CODEGEN` src/compiler/iyi/codegen/codegen.cr:2724
* user: `IYI_DUMP_PREOPT` src/compiler/iyi/compiler.cr:3794
* user: `IYI_DUMP_TYPE_ID` src/compiler/iyi/codegen/codegen.cr:841
* user: `IYI_DUMP_TYPE_INFO` src/compiler/iyi/codegen/codegen.cr:838
* user: `IYI_EXEC_PATH` test/compiler-cli/fixtures/iyi-echo_env.cr:1
* user: `IYI_FORK_CODEGEN` src/compiler/iyi/compiler.cr:2739
* user: `IYI_FORK_PROBE` src/compiler/iyi/compiler.cr:565
* user: `IYI_FORK_SELFTEST` src/compiler/iyi/compiler.cr:2689
* user: `IYI_FORK_TRACE` src/compiler/iyi/compiler.cr:2778
* user: `IYI_HEADER_CENSUS` src/compiler/iyi/codegen/gc_layouts.cr:73
* user: `IYI_INIT_SEED` src/compiler/iyi/semantic.cr:242
* user: `IYI_LIBRARY_PATH` bin/check-compiler-flag:20
* user: `IYI_LINK_DRIVER` src/compiler/iyi/compiler.cr:3250
* user: `IYI_LLVM_ARGS` src/compiler/iyi/compiler.cr:3784
* user: `IYI_LSP_ORIGIN` src/compiler/iyi/iyi_path.cr:82
* user: `IYI_MOD_MIRROR` src/compiler/iyi/mod/fetcher.cr:247
* user: `IYI_OPEN_TRAVEL` src/compiler/iyi/open_travel.cr:5
* user: `IYI_OPTS` src/compiler/iyi/command.cr:1223
* user: `IYI_PATH` src/compiler/iyi/command/daemon.cr:522
* user: `IYI_PREFIX` editors/vscode/CHANGELOG.md:10
* user: `IYI_PROF` src/compiler/iyi/progress_tracker.cr:5
* user: `IYI_SPEC_COMPILER_BIN` test/compiler-cli/test_helper.cr:25
* user: `IYI_SYM` src/compiler/iyi/codegen/fun.cr:340
* user: `IYI_TDF` src/compiler/iyi/codegen/fun.cr:70
* user: `IYI_VERIFY` src/compiler/iyi/compiler.cr:3788
* user: `IYI_WARM` src/compiler/iyi/compiler.cr:581
* user: `IYI_WASI_CC` src/compiler/iyi/command/sandbox.cr:108
* user: `IYI_WASMTIME` src/compiler/iyi/command/sandbox.cr:127
* user: `IYI_WORKERS` doc/drafts/ri-extension/DRAFT.md:80
* build: `IYI_ALLOCATING_PROGRAM` test/compiler/compiler_test.cr:11
* build: `IYI_ARM_EXP_CONFIG` test/cli/libm_oracle/math_config.h:10
* build: `IYI_ARRIVAL_ARGUMENT_HINTS` src/compiler/iyi/semantic/call_error.cr...
* build: `IYI_ARRIVAL_CALL_HINTS` src/compiler/iyi/semantic/call_error.cr:255
* build: `IYI_ARRIVAL_CONSTANT_HINTS` src/compiler/iyi/semantic/call_error.cr:96
* build: `IYI_ARRIVAL_METHOD_HINTS` src/compiler/iyi/semantic/call_error.cr:299
* build: `IYI_BIN` test/compiler-cli/iyi-daemon_test.cr:13
* build: `IYI_COMPILER_FLAGS` test/cli/collector_free_floor.sh:34
* build: `IYI_CONFIG_BUILD_COMMIT` Makefile:114
* build: `IYI_CONFIG_CC` src/compiler/iyi/compiler.cr:48
* build: `IYI_CONFIG_LIBRARY_PATH` Makefile:113
* build: `IYI_CONFIG_LLVM_VERSION` Makefile:587
* build: `IYI_CONFIG_PATH` Makefile:117
* build: `IYI_CONFIG_TARGET` Makefile:586
* build: `IYI_CORE_MATH_CONFIG` test/cli/libm_oracle/core_math/math_config.h:12
* build: `IYI_DAEMON_BIN` Makefile:178
* build: `IYI_DOCUMENTS` test/cli/doc_numbers.py:324
* build: `IYI_FILE` src/compiler/iyi/mod/sum.cr:28
* build: `IYI_LINK_OBJECTS` src/compiler/iyi/compiler.cr:3270
* build: `IYI_LINK_OUTPUT` src/compiler/iyi/compiler.cr:3264
* build: `IYI_MANIFEST` src/compiler/iyi/mod/installer.cr:20
* build: `IYI_MATH_PRIVATE` test/cli/libm_oracle/math_private.h:11
* build: `IYI_NEW_NAME` src/compiler/iyi/codegen/codegen.cr:14
* build: `IYI_ORACLE_CORE_MATH` test/cli/libm_oracle/oracle.c:34
* build: `IYI_ORACLE_STDBIT_H` test/cli/libm_oracle/stdbit.h:4
* build: `IYI_PACKAGE` Makefile:182
* build: `IYI_PACKAGE_LAYOUTS` test/compiler/iyi_import_test.cr:1440
* build: `IYI_PSEUDO_METHODS` src/compiler/iyi/semantic/call_error.cr:1405
* build: `IYI_REGEX_CONST_PREFIX` src/compiler/iyi/program.cr:862
* build: `IYI_REGEX_FLAGS` src/compiler/iyi/semantic/literal_expander.cr:400
* build: `IYI_ROOT` bin/iyi.bat:16
* build: `IYI_RUST_MACROS` src/compiler/iyi/syntax/parser.cr:6289
* build: `IYI_RUST_TYPE_SPELLINGS` src/compiler/iyi/syntax/parser.cr:7803
* build: `IYI_RUST_WRAPPERS` src/compiler/iyi/syntax/parser.cr:2631
* build: `IYI_SPECS` test/cli/doc_numbers.py:91
* build: `IYI_SPELLINGS` src/compiler/iyi/syntax/parser.cr:9302
* build: `IYI_STD_DECLARERS` src/compiler/iyi/semantic/call_error.cr:178
* build: `IYI_STD_NUMBER_MODULES` src/compiler/iyi/semantic/call_error.cr:1087
* build: `IYI_TYPE_SPELLINGS` src/compiler/iyi/syntax/parser.cr:7798
* build: `IYI_VERSION` Makefile:47
* build: `IYI_X` doc/drafts/ri-extension/DRAFT.md:79
* runtime: `IYI_CLONE_FLAGS` src/iyi/thread.iyi:153
* runtime: `IYI_FUTEX_WAIT` src/iyi/thread.iyi:170
* runtime: `IYI_FUTEX_WAKE` src/iyi/thread.iyi:171
* runtime: `IYI_MC_COUNT` src/iyi/thread.iyi:355
* runtime: `IYI_MC_PC` src/iyi/thread.iyi:357
* runtime: `IYI_MC_REGS` src/iyi/thread.iyi:354
* runtime: `IYI_MC_SP` src/iyi/thread.iyi:356
* runtime: `IYI_POLL_DATA_OFFSET` src/iyi/concurrency.iyi:217
* runtime: `IYI_POLL_EVENT_BYTES` src/iyi/concurrency.iyi:218
* runtime: `IYI_SA_FLAGS` src/iyi/thread.iyi:120
* runtime: `IYI_SA_WORD` src/iyi/thread.iyi:349
* runtime: `IYI_SG_ABOVE` src/iyi/concurrency.iyi:4547
* runtime: `IYI_SG_ALT_BYTES` src/iyi/concurrency.iyi:4544
* runtime: `IYI_SG_BELOW` src/iyi/concurrency.iyi:4548
* runtime: `IYI_SG_SA_FLAGS` src/iyi/concurrency.iyi:4527
* runtime: `IYI_SG_SIGBUS` src/iyi/concurrency.iyi:4540
* runtime: `IYI_SG_SIGSEGV` src/iyi/concurrency.iyi:4535
* runtime: `IYI_SG_SYS_RT_SIGACTION` src/iyi/concurrency.iyi:4523
* runtime: `IYI_SG_SYS_SIGALTSTACK` src/iyi/concurrency.iyi:4524
* runtime: `IYI_SG_UC_SP` src/iyi/concurrency.iyi:4528
* runtime: `IYI_SIGSTOP_THE_WORLD` src/iyi/thread.iyi:169
* runtime: `IYI_SYS_CLOCK_GETTIME` src/iyi/concurrency.iyi:238
* runtime: `IYI_SYS_CLONE` src/iyi/thread.iyi:107
* runtime: `IYI_SYS_EPOLL_CREATE1` src/iyi/concurrency.iyi:242
* runtime: `IYI_SYS_EPOLL_CTL` src/iyi/concurrency.iyi:239
* runtime: `IYI_SYS_EPOLL_PWAIT` src/iyi/concurrency.iyi:240
* runtime: `IYI_SYS_EVENTFD2` src/iyi/concurrency.iyi:241
* runtime: `IYI_SYS_EXIT` src/iyi/thread.iyi:108
* runtime: `IYI_SYS_FUTEX` src/iyi/thread.iyi:109
* runtime: `IYI_SYS_GETAFFINITY` src/iyi/thread.iyi:115
* runtime: `IYI_SYS_GETPID` src/iyi/thread.iyi:110
* runtime: `IYI_SYS_GETTID` src/iyi/thread.iyi:111
* runtime: `IYI_SYS_MMAP` src/iyi/concurrency.iyi:236
* runtime: `IYI_SYS_MPROTECT` src/iyi/concurrency.iyi:237
* runtime: `IYI_SYS_RT_SIGACTION` src/iyi/thread.iyi:113
* runtime: `IYI_SYS_SCHED_YIELD` src/iyi/thread.iyi:114
* runtime: `IYI_SYS_TGKILL` src/iyi/thread.iyi:112
* runtime: `IYI_TC_PID` src/iyi/thread.iyi:103
* runtime: `IYI_TC_RESUME` src/iyi/thread.iyi:102
* runtime: `IYI_TC_RESUMED` src/iyi/thread.iyi:101
* runtime: `IYI_TC_SUSPENDED` src/iyi/thread.iyi:100
* runtime: `IYI_THREAD_LINE` src/iyi/thread.iyi:68
* runtime: `IYI_THREAD_STACK` src/iyi/thread.iyi:69
* runtime: `IYI_TL_CACHE` src/iyi/thread.iyi:94
* runtime: `IYI_TL_HANDLE` doc/drafts/ri-extension/DRAFT.md:51
* runtime: `IYI_TL_LOW` src/iyi/thread.iyi:88
* runtime: `IYI_TL_NEXT` src/iyi/thread.iyi:87
* runtime: `IYI_TL_OBJECT` src/iyi/thread.iyi:93
* runtime: `IYI_TL_PARK` src/iyi/thread.iyi:90
* runtime: `IYI_TL_PC` src/iyi/thread.iyi:92
* runtime: `IYI_TL_SP` src/iyi/thread.iyi:91
* runtime: `IYI_TL_SPILL` src/iyi/thread.iyi:95
* runtime: `IYI_TL_SPILL_END` src/iyi/thread.iyi:96
* runtime: `IYI_TL_TOP` src/iyi/thread.iyi:89
* runtime: `IYI_UC_COUNT` src/iyi/thread.iyi:125
* runtime: `IYI_UC_MCONTEXT` src/iyi/thread.iyi:353
* runtime: `IYI_UC_PC` src/iyi/thread.iyi:127
* runtime: `IYI_UC_REGS` src/iyi/thread.iyi:124
* runtime: `IYI_UC_SP` src/iyi/thread.iyi:126
* runtime: `IYI_WAKE_ADD` src/iyi/concurrency.iyi:233
* runtime: `IYI_WAKE_FILTER` src/iyi/concurrency.iyi:232
* runtime: `IYI_WAKE_IDENT` src/iyi/concurrency.iyi:231
* runtime: `IYI_WAKE_TRIGGER` src/iyi/concurrency.iyi:234
* runtime: `IYI_WIN_ACCESS_VIOLATION` src/iyi/prelude.iyi:2915
* runtime: `IYI_WIN_ENVVAR_NOT_FOUND` src/iyi/prelude.iyi:2592
* runtime: `IYI_WIN_GUARD_PAGE` src/iyi/prelude.iyi:2916
* runtime: `IYI_WIN_PATH_LIMIT` src/iyi/prelude.iyi:907
* runtime: `IYI_WIN_STACK_OVERFLOW` src/iyi/prelude.iyi:2914
* test data: `IYI_EXEC_VALUE` test/cli/std_process_exercise.iyi:133
* test data: `IYI_FILE_SANDBOX` test/cli/std_file_exercise.iyi:33
* test data: `IYI_MATH_FMA_DOUBLES` test/cli/std_math_exercise.iyi:495
* test data: `IYI_MATH_FMA_SINGLES` test/cli/std_math_exercise.iyi:496
* test data: `IYI_NOT_UTF8` test/cli/std_process_exercise.iyi:556
* test data: `IYI_ORDER` test/cli/std_process_exercise.iyi:415
* test data: `IYI_ORDER1` test/cli/std_process_exercise.iyi:415
* test data: `IYI_PROBE_TR` src/iyi/prelude.iyi:2507
* test data: `IYI_PROCESS_GIVEN` test/cli/std_process_exercise.iyi:363
* test data: `IYI_PROCESS_PROBE` test/cli/std_process_exercise.iyi:357
* test data: `IYI_PROCESS_TWICE` test/cli/std_process_exercise.iyi:383
* test data: `IYI_PROXY_PROBE` test/cli/std_http_proxy_exercise.iyi:28
* test data: `IYI_TOLD` test/cli/windows_exercise.sh:147
* prose: `IYI_X` doc/drafts/ri-extension/DRAFT.md:79
