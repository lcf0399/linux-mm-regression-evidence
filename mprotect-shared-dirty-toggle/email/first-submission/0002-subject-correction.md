# mprotect 第二封邮件标题更正模板

> 用法：打开“已发送”里的第二封 mprotect 邮件，点“回复全部”。如果 Webmail 允许编辑主题，把主题改成：
>
> ```text
> Re: [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12
> ```
>
> 然后只发送下面正文。不要附附件。

```text
Sorry, I sent the previous report with the wrong subject line.

The intended subject is:

  [REGRESSION] mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12

The body and evidence links in that message are for the mprotect
shared-dirty PTE toggle regression. Please treat it as the mprotect
report, not as a MADV_PAGEOUT report.

#regzbot title: mm/mprotect: shared dirty PTE toggle takes ~1.6x longer on v6.19 than v6.12

Sorry for the noise.
```
