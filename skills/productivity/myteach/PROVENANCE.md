# 来源与更新策略（fork 版）

## 这是什么

`myteach` = 上游 `teach` 的**本地定制分支**。与上游的唯一区别：

- `SKILL.md` 里的 **Hard Rules (non-negotiable)** 八条
- `TEACHING-PITFALLS.md`（每条规则背后的真实案例与证据）

其余内容（mission / ZPD / 知识 vs 技能 / reference / learning-records）与上游一致，随上游更新。

## 仓库布局

```
origin   = git@github.com:<you>/skills.git       ← 你的 fork，日常提交在这里
upstream = https://github.com/mattpocock/skills.git  ← 上游，只读
分支      = local（main 保持与上游一致，便于 diff）
```

在 fork 里 **`teach` 与 `myteach` 同时存在**，且路径独立：

```
skills/productivity/teach/     ← 纯净上游版，可随时更新
skills/productivity/myteach/   ← 你的版本
```

**故意不把 `teach/` 改名成 `myteach/`**：改名在 git 看来是 delete + add，上游此后对 `teach` 的改动就无法干净合并。独立路径下你可以精确查看上游改了什么，再决定要不要搬进 `myteach`。

## 吸收上游更新

```bash
cd <fork checkout>
git fetch upstream
git log --stat upstream/main -- skills/productivity/teach/   # 上游对 teach 改了什么
# 只挑有价值的改动，手工并进 skills/productivity/myteach/
git merge upstream/main                                      # 同步整个仓库（teach 自动最新）
```

`local` 分支上的 `myteach` 提交不会被 `git merge` 覆盖；只有 `git reset --hard` 才会。

## 在新机器上安装

```bash
git clone https://github.com/<you>/skills.git ~/Codes/skills
cd ~/Codes/skills
git remote add upstream https://github.com/mattpocock/skills.git
git checkout local
bash scripts/link-skills.sh        # 把仓库里的 skill 链进 ~/.claude/skills 与 ~/.agents/skills
```

`link-skills.sh` 不认识 `myteach` 之外的自定义名字也无所谓 —— 它按仓库里的目录名安装，
所以 `myteach` 会被正常链进去。它**不会**碰仓库里没有的 skill（例如本地自建的 `save-session`），
但会 `rm -rf` 并重建仓库中**同名**的 skill 目录，所以本地手改务必先提交到 fork。

## 为什么用 fork 而不是本地目录

| | 本地实体目录 | fork + local 分支 |
|---|---|---|
| 多机器同步 | 手工拷贝 | `git clone` |
| 版本历史 | 无 | 每次加规则一个 commit |
| 回退 | 手抄 | `git checkout` / `git revert` |
| 回馈上游 | 不可能 | 可开 PR（把 `myteach` 的通用部分提给上游） |
