# Oracle 19c ASM 冗余度与磁盘添加实验详细报告

## 一、实验信息

| 项目 | 内容 |
|------|------|
| 实验日期 | 2026-02-03 14:08:48 |
| 实验环境 | Oracle 19c ASM on Docker |
| 容器名称 | oracle19casmlhr |
| 主机名 | lhr2019ocpasm |
| 服务器IP | (内网实验环境) |

## 二、实验目的

测试Oracle ASM在不同冗余度(EXTERNAL/NORMAL/HIGH)下：
1. 是否支持指定failgroup
2. 是否支持添加不同大小的磁盘
3. 添加磁盘失败时的错误信息

---

## 三、环境准备

### 3.1 创建测试磁盘文件

```bash
# 创建测试目录
mkdir -p /test_asm
cd /test_asm

# 创建不同大小的磁盘文件
dd if=/dev/zero of=d1 bs=1M count=500    # 500MB
dd if=/dev/zero of=d2 bs=1M count=500    # 500MB  
dd if=/dev/zero of=d3 bs=1M count=500    # 500MB
dd if=/dev/zero of=d4 bs=1M count=500    # 500MB
dd if=/dev/zero of=d5 bs=1M count=1000   # 1GB
dd if=/dev/zero of=d6 bs=1M count=200    # 200MB
```

### 3.2 配置loop设备

```bash
# 创建loop设备节点
for i in 40 41 42 43 44 45; do
    mknod -m 0660 /dev/loop$i b 7 $i
done

# 绑定loop设备到磁盘文件
losetup /dev/loop40 /test_asm/d1
losetup /dev/loop41 /test_asm/d2
losetup /dev/loop42 /test_asm/d3
losetup /dev/loop43 /test_asm/d4
losetup /dev/loop44 /test_asm/d5
losetup /dev/loop45 /test_asm/d6
```

### 3.3 创建ASM磁盘

```bash
# 使用oracleasm创建ASM磁盘
oracleasm createdisk TDISK1 /dev/loop40
oracleasm createdisk TDISK2 /dev/loop41
oracleasm createdisk TDISK3 /dev/loop42
oracleasm createdisk TDISK4 /dev/loop43
oracleasm createdisk TDISK5 /dev/loop44
oracleasm createdisk TDISK6 /dev/loop45
oracleasm scandisks
```

**测试磁盘配置：**
- TDISK1-4: 各500MB
- TDISK5: 1GB
- TDISK6: 200MB

---

## 四、实验1：EXTERNAL冗余度测试

### 4.1 创建EXTERNAL磁盘组（1个磁盘）

**执行SQL：**
```sql
CREATE DISKGROUP TGRP_EXT EXTERNAL REDUNDANCY 
DISK 'ORCL:TDISK1' 
ATTRIBUTE 'compatible.asm'='19.0';
```

**运行结果：**
```
Diskgroup created.
```
✅ **成功** - EXTERNAL冗余度只需1个磁盘即可创建

---

### 4.2 添加相同大小磁盘（500MB）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_EXT ADD DISK 'ORCL:TDISK2';
```

**运行结果：**
```
Diskgroup altered.
```
✅ **成功** - 可以添加相同大小的磁盘

---

### 4.3 添加更大磁盘（1GB）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_EXT ADD DISK 'ORCL:TDISK5';
```

**运行结果：**
```
Diskgroup altered.
```
✅ **成功** - EXTERNAL冗余度支持添加更大的磁盘

---

### 4.4 添加更小磁盘（200MB）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_EXT ADD DISK 'ORCL:TDISK6';
```

**运行结果：**
```
Diskgroup altered.
```
✅ **成功** - EXTERNAL冗余度支持添加更小的磁盘

---

### 4.5 尝试指定failgroup（EXTERNAL不支持）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_EXT ADD FAILGROUP fg1 DISK 'ORCL:TDISK3';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_EXT ADD FAILGROUP fg1 DISK 'ORCL:TDISK3'
*
ERROR at line 1:
ORA-15067: command or option incompatible with diskgroup redundancy
```
❌ **失败** - EXTERNAL冗余度不支持指定failgroup

---

### 4.6 查看磁盘组状态

**执行SQL：**
```sql
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup WHERE name='TGRP_EXT';
SELECT name, path, failgroup, total_mb FROM v$asm_disk 
WHERE group_number=(SELECT group_number FROM v$asm_diskgroup WHERE name='TGRP_EXT');
```

**运行结果：**
```
NAME         STATE       TYPE    TOTAL_MB    FREE_MB
------------ ----------- ------ ---------- ----------
TGRP_EXT     MOUNTED     EXTERN       2200       2137

NAME         PATH                  FAILGROUP         TOTAL_MB
------------ -------------------- --------------- ----------
TDISK1       ORCL:TDISK1          TDISK1                 500
TDISK2       ORCL:TDISK2          TDISK2                 500
TDISK5       ORCL:TDISK5          TDISK5                1000
TDISK6       ORCL:TDISK6          TDISK6                 200
```

**观察：** EXTERNAL冗余度下，每个磁盘自动成为独立的failgroup（以磁盘名命名），但不支持手动指定failgroup

---

### 4.7 EXTERNAL实验结论

| 测试项 | 结果 | 错误码 |
|--------|------|--------|
| 创建磁盘组(1个磁盘) | ✅ 成功 | - |
| 添加相同大小磁盘 | ✅ 成功 | - |
| 添加更大磁盘(1GB) | ✅ 成功 | - |
| 添加更小磁盘(200MB) | ✅ 成功 | - |
| 指定failgroup | ❌ 失败 | ORA-15067 |

**结论：EXTERNAL冗余度可以自由混合不同大小磁盘，但不支持指定failgroup**

---

## 五、实验2：NORMAL冗余度测试

### 5.1 创建NORMAL磁盘组（2个failgroup）

**执行SQL：**
```sql
CREATE DISKGROUP TGRP_NORM NORMAL REDUNDANCY 
FAILGROUP fg1 DISK 'ORCL:TDISK1'
FAILGROUP fg2 DISK 'ORCL:TDISK2'
ATTRIBUTE 'compatible.asm'='19.0';
```

**运行结果：**
```
Diskgroup created.
```
✅ **成功** - NORMAL冗余度至少需要2个failgroup

---

### 5.2 添加磁盘到已有failgroup（fg1）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg1 DISK 'ORCL:TDISK3';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg1 DISK 'ORCL:TDISK3'
*
ERROR at line 1:
ORA-15032: not all alterations performed
ORA-15411: Failure groups in disk group TGRP_NORM have different number of disks.
```
❌ **失败** - NORMAL冗余度要求各failgroup的磁盘数量一致

---

### 5.3 添加磁盘到新failgroup（fg3）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg3 DISK 'ORCL:TDISK4';
```

**运行结果：**
```
Diskgroup altered.
```
✅ **成功** - 可以动态添加新的failgroup

---

### 5.4 不指定failgroup添加（自动分配）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_NORM ADD DISK 'ORCL:TDISK5';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_NORM ADD DISK 'ORCL:TDISK5'
*
ERROR at line 1:
ORA-15032: not all alterations performed
ORA-15410: Disks in disk group TGRP_NORM do not have equal size.
```
❌ **失败** - NORMAL冗余度不支持添加不同大小的磁盘（TDISK5是1GB，现有磁盘是500MB）

---

### 5.5 添加更小磁盘到fg2（200MB vs 500MB）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg2 DISK 'ORCL:TDISK6';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg2 DISK 'ORCL:TDISK6'
*
ERROR at line 1:
ORA-15032: not all alterations performed
ORA-15410: Disks in disk group TGRP_NORM do not have equal size.
```
❌ **失败** - NORMAL冗余度不支持添加更小的磁盘

---

### 5.6 查看磁盘组状态

**执行SQL：**
```sql
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup WHERE name='TGRP_NORM';
SELECT name, path, failgroup, total_mb FROM v$asm_disk 
WHERE group_number=(SELECT group_number FROM v$asm_diskgroup WHERE name='TGRP_NORM') ORDER BY failgroup;
```

**运行结果：**
```
NAME                           STATE       TYPE     TOTAL_MB    FREE_MB
------------------------------ ----------- ------ ---------- ----------
TGRP_NORM                      MOUNTED     NORMAL       1500       1379

NAME       PATH           FAILGROUP        TOTAL_MB
---------- -------------- --------------- ----------
TDISK1     ORCL:TDISK1    FG1                   500
TDISK2     ORCL:TDISK2    FG2                   500
TDISK4     ORCL:TDISK4    FG3                   500
```

---

### 5.7 NORMAL实验结论

| 测试项 | 结果 | 错误码 |
|--------|------|--------|
| 创建磁盘组(2个FG) | ✅ 成功 | - |
| 添加到已有FG | ❌ 失败 | ORA-15411 |
| 添加到新FG(相同大小) | ✅ 成功 | - |
| 添加不同大小磁盘(1GB) | ❌ 失败 | ORA-15410 |
| 添加更小磁盘(200MB) | ❌ 失败 | ORA-15410 |

**结论：NORMAL冗余度不支持混合不同大小磁盘，且各failgroup的磁盘数量需要一致**

---

## 六、实验3：HIGH冗余度测试

### 6.1 尝试用2个failgroup创建HIGH（应该失败）

**执行SQL：**
```sql
CREATE DISKGROUP TGRP_HIGH_BAD HIGH REDUNDANCY
FAILGROUP fg1 DISK 'ORCL:TDISK1'
FAILGROUP fg2 DISK 'ORCL:TDISK2'
ATTRIBUTE 'compatible.asm'='19.0';
```

**运行结果：**
```
CREATE DISKGROUP TGRP_HIGH_BAD HIGH REDUNDANCY
*
ERROR at line 1:
ORA-15018: diskgroup cannot be created
ORA-15167: command requires at least 3 failure groups; found only 2
```
❌ **失败** - HIGH冗余度至少需要3个failgroup

---

### 6.2 用3个failgroup创建HIGH

**执行SQL：**
```sql
CREATE DISKGROUP TGRP_HIGH HIGH REDUNDANCY
FAILGROUP fg1 DISK 'ORCL:TDISK1'
FAILGROUP fg2 DISK 'ORCL:TDISK2'
FAILGROUP fg3 DISK 'ORCL:TDISK3'
ATTRIBUTE 'compatible.asm'='19.0';
```

**运行结果：**
```
Diskgroup created.
```
✅ **成功** - HIGH冗余度需要至少3个failgroup

---

### 6.3 添加磁盘到新failgroup（fg4）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_HIGH ADD FAILGROUP fg4 DISK 'ORCL:TDISK4';
```

**运行结果：**
```
Diskgroup altered.
```
✅ **成功** - 可以动态添加新的failgroup

---

### 6.4 添加不同大小磁盘（1GB）到fg1

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_HIGH ADD FAILGROUP fg1 DISK 'ORCL:TDISK5';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_HIGH ADD FAILGROUP fg1 DISK 'ORCL:TDISK5'
*
ERROR at line 1:
ORA-15032: not all alterations performed
ORA-15410: Disks in disk group TGRP_HIGH do not have equal size.
```
❌ **失败** - HIGH冗余度也不支持添加不同大小的磁盘

---

### 6.5 查看磁盘组状态

**执行SQL：**
```sql
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup WHERE name='TGRP_HIGH';
SELECT name, path, failgroup, total_mb FROM v$asm_disk 
WHERE group_number=(SELECT group_number FROM v$asm_diskgroup WHERE name='TGRP_HIGH') ORDER BY failgroup;
```

**运行结果：**
```
NAME                           STATE       TYPE     TOTAL_MB    FREE_MB
------------------------------ ----------- ------ ---------- ----------
TGRP_HIGH                      MOUNTED     HIGH         2000       1817

NAME       PATH           FAILGROUP        TOTAL_MB
---------- -------------- --------------- ----------
TDISK1     ORCL:TDISK1    FG1                   500
TDISK2     ORCL:TDISK2    FG2                   500
TDISK3     ORCL:TDISK3    FG3                   500
TDISK4     ORCL:TDISK4    FG4                   500
```

---

### 6.6 HIGH实验结论

| 测试项 | 结果 | 错误码 |
|--------|------|--------|
| 用2个FG创建 | ❌ 失败 | ORA-15167 |
| 用3个FG创建 | ✅ 成功 | - |
| 添加到新FG(相同大小) | ✅ 成功 | - |
| 添加不同大小磁盘(1GB) | ❌ 失败 | ORA-15410 |

**结论：HIGH冗余度至少需要3个failgroup，且不支持混合不同大小磁盘**

---

## 七、实验4：边界条件测试

### 7.1 创建测试磁盘组

**执行SQL：**
```sql
CREATE DISKGROUP TGRP_TEST EXTERNAL REDUNDANCY DISK 'ORCL:TDISK1' ATTRIBUTE 'compatible.asm'='19.0';
```

**运行结果：**
```
Diskgroup created.
```

---

### 7.2 添加已在组中的磁盘（预期失败）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_TEST ADD DISK 'ORCL:TDISK1';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_TEST ADD DISK 'ORCL:TDISK1'
*
ERROR at line 1:
ORA-15032: not all alterations performed
ORA-15029: disk 'ORCL:TDISK1' is already mounted by this instance
```
❌ **失败** - 磁盘已经在磁盘组中，不能重复添加

---

### 7.3 添加不存在的磁盘（预期失败）

**执行SQL：**
```sql
ALTER DISKGROUP TGRP_TEST ADD DISK 'ORCL:NOTEXIST';
```

**运行结果：**
```
ALTER DISKGROUP TGRP_TEST ADD DISK 'ORCL:NOTEXIST'
*
ERROR at line 1:
ORA-15032: not all alterations performed
ORA-15031: disk specification 'ORCL:NOTEXIST' matches no disks
```
❌ **失败** - 指定的磁盘不存在

---

### 7.4 用已占用磁盘创建新组（预期失败）

**执行SQL：**
```sql
CREATE DISKGROUP TGRP_DUP EXTERNAL REDUNDANCY DISK 'ORCL:TDISK1' ATTRIBUTE 'compatible.asm'='19.0';
```

**运行结果：**
```
CREATE DISKGROUP TGRP_DUP EXTERNAL REDUNDANCY DISK 'ORCL:TDISK1' ATTRIBUTE 'compatible.asm'='19.0'
*
ERROR at line 1:
ORA-15018: diskgroup cannot be created
ORA-15029: disk 'ORCL:TDISK1' is already mounted by this instance
```
❌ **失败** - 磁盘已被其他磁盘组占用

---

## 八、错误码汇总

| 错误码 | 错误信息 | 触发场景 |
|--------|----------|----------|
| ORA-15067 | command or option incompatible with diskgroup redundancy | EXTERNAL冗余度指定failgroup |
| ORA-15167 | command requires at least 3 failure groups | HIGH冗余度用少于3个FG |
| ORA-15410 | Disks in disk group do not have equal size | NORMAL/HIGH添加不同大小磁盘 |
| ORA-15411 | Failure groups have different number of disks | NORMAL向已有FG单独添加磁盘 |
| ORA-15018 | diskgroup cannot be created | 创建磁盘组失败（多种原因） |
| ORA-15029 | disk is already mounted by this instance | 磁盘已被占用 |
| ORA-15031 | disk specification matches no disks | 磁盘不存在 |
| ORA-15032 | not all alterations performed | 操作未完成（前置条件不满足） |

---

## 九、实验总结

### 9.1 结论对照表

| 冗余度 | 最少磁盘/FG | 支持failgroup | 混合大小磁盘 | FG磁盘数要求 |
|--------|-------------|---------------|--------------|--------------|
| EXTERNAL | 1个磁盘 | ❌ 不支持 | ✅ 支持 | 无 |
| NORMAL | 2个FG | ✅ 支持 | ❌ 不支持 | 各FG数量需一致 |
| HIGH | 3个FG | ✅ 支持 | ❌ 不支持 | 各FG数量需一致 |

### 9.2 关键发现

1. **EXTERNAL冗余度**：
   - 不支持指定failgroup（ORA-15067）
   - 可以自由混合不同大小的磁盘
   - 适合测试环境或对数据安全性要求不高的场景

2. **NORMAL冗余度**：
   - 至少需要2个failgroup
   - **不支持混合不同大小磁盘**（ORA-15410）
   - **各failgroup的磁盘数量必须一致**（ORA-15411）
   - 生产环境推荐使用

3. **HIGH冗余度**：
   - 至少需要3个failgroup（ORA-15167）
   - **不支持混合不同大小磁盘**（ORA-15410）
   - 对数据极度重要的场景使用

### 9.3 最佳实践建议

1. 添加磁盘前，先用 `v$asm_disk` 确认磁盘状态和大小
2. NORMAL/HIGH冗余度必须确保所有磁盘大小一致
3. NORMAL/HIGH添加磁盘时，建议同时向所有failgroup添加相同数量的磁盘
4. 使用 `oracleasm listdisks` 确认ASM磁盘可用性

---

## 十、环境清理

```bash
# 删除ASM磁盘
oracleasm deletedisk TDISK1
oracleasm deletedisk TDISK2
oracleasm deletedisk TDISK3
oracleasm deletedisk TDISK4
oracleasm deletedisk TDISK5
oracleasm deletedisk TDISK6

# 解绑loop设备
for i in 40 41 42 43 44 45; do
    losetup -d /dev/loop$i
done

# 删除测试目录
rm -rf /test_asm
```

---

**报告生成时间：** 2026-02-03 14:08  
**实验日志文件：** /tmp/asm_final_20260203_140848.log
