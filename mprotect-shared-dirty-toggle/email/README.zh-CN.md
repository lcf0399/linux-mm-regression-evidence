# mprotect shared-dirty 邮件记录

这里保存 `mprotect-shared-dirty-toggle` 相关的上游邮件草稿、回复草稿和中文审阅说明。

当前目录分两部分：

- `0001-mprotect-shared-dirty-baremetal-v617-regression*.md`：准备重新发给上游的
  bare-metal 版主邮件草稿，使用当前真机复跑、`v6.16 -> v6.17` narrowing 和
  `v6.17` single-PTE attribution probe。
- `first-submission/`：第一次提交和后续回复草稿归档。那一轮主要记录 QEMU/lab 证据、
  simple reproducer、synthetic workload 讨论和 Pedro/David/Lorenzo follow-up。

发送新邮件前需要：

- push 当前 evidence bundle。
- 把英文草稿里的 `FIXME` 替换成固定 GitHub commit URL。
- 再次确认 `scripts/get_maintainer.pl --no-rolestats -f mm/mprotect.c` 的收件人没有变化。

当前真机复跑、release-window narrowing 和 attribution probe 结论以 `bare-metal/`
与 `analysis/` 下的文档为准。
