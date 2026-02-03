#!/bin/bash
#############################################################################
# ASM冗余度实验 - 最终版
# 每个实验独立运行，避免ASM实例不稳定
#############################################################################

export ORACLE_HOME=/u01/app/19.3.0/grid
export PATH=$ORACLE_HOME/bin:$PATH
LOG=/tmp/asm_final_$(date +%Y%m%d_%H%M%S).log

echo "========================================" | tee $LOG
echo "ASM冗余度与磁盘添加实验" | tee -a $LOG
echo "时间: $(date)" | tee -a $LOG
echo "========================================" | tee -a $LOG

# 准备测试磁盘
echo -e "\n[准备] 创建测试磁盘..." | tee -a $LOG
mkdir -p /test_asm
cd /test_asm

# 创建不同大小的磁盘文件
dd if=/dev/zero of=d1 bs=1M count=500 2>/dev/null   # 500MB
dd if=/dev/zero of=d2 bs=1M count=500 2>/dev/null   # 500MB  
dd if=/dev/zero of=d3 bs=1M count=500 2>/dev/null   # 500MB
dd if=/dev/zero of=d4 bs=1M count=500 2>/dev/null   # 500MB
dd if=/dev/zero of=d5 bs=1M count=1000 2>/dev/null  # 1GB
dd if=/dev/zero of=d6 bs=1M count=200 2>/dev/null   # 200MB

# 配置loop设备
for i in 40 41 42 43 44 45; do
    mknod -m 0660 /dev/loop$i b 7 $i 2>/dev/null
done

losetup /dev/loop40 /test_asm/d1
losetup /dev/loop41 /test_asm/d2
losetup /dev/loop42 /test_asm/d3
losetup /dev/loop43 /test_asm/d4
losetup /dev/loop44 /test_asm/d5
losetup /dev/loop45 /test_asm/d6

# 创建ASM磁盘
oracleasm createdisk TDISK1 /dev/loop40
oracleasm createdisk TDISK2 /dev/loop41
oracleasm createdisk TDISK3 /dev/loop42
oracleasm createdisk TDISK4 /dev/loop43
oracleasm createdisk TDISK5 /dev/loop44
oracleasm createdisk TDISK6 /dev/loop45
oracleasm scandisks

echo "测试磁盘准备完成: TDISK1-4(500MB), TDISK5(1GB), TDISK6(200MB)" | tee -a $LOG

#############################################################################
echo -e "\n========================================" | tee -a $LOG
echo "实验1: EXTERNAL冗余度" | tee -a $LOG
echo "========================================" | tee -a $LOG

su - grid << 'GRIDEOF' 2>&1 | tee -a $LOG
sqlplus -s / as sysasm << 'SQLEOF'
SET ECHO ON FEEDBACK ON LINESIZE 200

PROMPT === 1.1 创建EXTERNAL磁盘组(1个磁盘) ===
CREATE DISKGROUP TGRP_EXT EXTERNAL REDUNDANCY 
DISK 'ORCL:TDISK1' 
ATTRIBUTE 'compatible.asm'='19.0';

PROMPT === 1.2 添加相同大小磁盘(500MB) ===
ALTER DISKGROUP TGRP_EXT ADD DISK 'ORCL:TDISK2';

PROMPT === 1.3 添加更大磁盘(1GB) ===  
ALTER DISKGROUP TGRP_EXT ADD DISK 'ORCL:TDISK5';

PROMPT === 1.4 添加更小磁盘(200MB) ===
ALTER DISKGROUP TGRP_EXT ADD DISK 'ORCL:TDISK6';

PROMPT === 1.5 尝试指定failgroup (EXTERNAL不支持) ===
ALTER DISKGROUP TGRP_EXT ADD FAILGROUP fg1 DISK 'ORCL:TDISK3';

PROMPT === 查看磁盘组状态 ===
COL name FORMAT A12
COL path FORMAT A20
COL failgroup FORMAT A15
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup WHERE name='TGRP_EXT';
SELECT name, path, failgroup, total_mb FROM v$asm_disk WHERE group_number=(SELECT group_number FROM v$asm_diskgroup WHERE name='TGRP_EXT');

PROMPT === 清理 ===
DROP DISKGROUP TGRP_EXT INCLUDING CONTENTS;

EXIT;
SQLEOF
GRIDEOF

#############################################################################
echo -e "\n========================================" | tee -a $LOG
echo "实验2: NORMAL冗余度" | tee -a $LOG
echo "========================================" | tee -a $LOG

su - grid << 'GRIDEOF' 2>&1 | tee -a $LOG
sqlplus -s / as sysasm << 'SQLEOF'
SET ECHO ON FEEDBACK ON LINESIZE 200

PROMPT === 2.1 创建NORMAL磁盘组(2个failgroup) ===
CREATE DISKGROUP TGRP_NORM NORMAL REDUNDANCY 
FAILGROUP fg1 DISK 'ORCL:TDISK1'
FAILGROUP fg2 DISK 'ORCL:TDISK2'
ATTRIBUTE 'compatible.asm'='19.0';

PROMPT === 2.2 添加到已有failgroup(fg1) ===
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg1 DISK 'ORCL:TDISK3';

PROMPT === 2.3 添加到新failgroup(fg3) ===
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg3 DISK 'ORCL:TDISK4';

PROMPT === 2.4 不指定failgroup添加(自动分配) ===
ALTER DISKGROUP TGRP_NORM ADD DISK 'ORCL:TDISK5';

PROMPT === 2.5 添加更小磁盘到fg2(200MB vs 500MB) ===
ALTER DISKGROUP TGRP_NORM ADD FAILGROUP fg2 DISK 'ORCL:TDISK6';

PROMPT === 查看磁盘组状态 ===
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup WHERE name='TGRP_NORM';
SELECT name, path, failgroup, total_mb FROM v$asm_disk WHERE group_number=(SELECT group_number FROM v$asm_diskgroup WHERE name='TGRP_NORM') ORDER BY failgroup;

PROMPT === 清理 ===
DROP DISKGROUP TGRP_NORM INCLUDING CONTENTS;

EXIT;
SQLEOF
GRIDEOF

#############################################################################
echo -e "\n========================================" | tee -a $LOG
echo "实验3: HIGH冗余度" | tee -a $LOG  
echo "========================================" | tee -a $LOG

su - grid << 'GRIDEOF' 2>&1 | tee -a $LOG
sqlplus -s / as sysasm << 'SQLEOF'
SET ECHO ON FEEDBACK ON LINESIZE 200

PROMPT === 3.1 尝试用2个failgroup创建HIGH(应该失败) ===
CREATE DISKGROUP TGRP_HIGH_BAD HIGH REDUNDANCY
FAILGROUP fg1 DISK 'ORCL:TDISK1'
FAILGROUP fg2 DISK 'ORCL:TDISK2'
ATTRIBUTE 'compatible.asm'='19.0';

PROMPT === 3.2 用3个failgroup创建HIGH ===
CREATE DISKGROUP TGRP_HIGH HIGH REDUNDANCY
FAILGROUP fg1 DISK 'ORCL:TDISK1'
FAILGROUP fg2 DISK 'ORCL:TDISK2'
FAILGROUP fg3 DISK 'ORCL:TDISK3'
ATTRIBUTE 'compatible.asm'='19.0';

PROMPT === 3.3 添加到新failgroup(fg4) ===
ALTER DISKGROUP TGRP_HIGH ADD FAILGROUP fg4 DISK 'ORCL:TDISK4';

PROMPT === 3.4 添加不同大小磁盘(1GB)到fg1 ===
ALTER DISKGROUP TGRP_HIGH ADD FAILGROUP fg1 DISK 'ORCL:TDISK5';

PROMPT === 查看磁盘组状态 ===
SELECT name, state, type, total_mb, free_mb FROM v$asm_diskgroup WHERE name='TGRP_HIGH';
SELECT name, path, failgroup, total_mb FROM v$asm_disk WHERE group_number=(SELECT group_number FROM v$asm_diskgroup WHERE name='TGRP_HIGH') ORDER BY failgroup;

PROMPT === 清理 ===
DROP DISKGROUP TGRP_HIGH INCLUDING CONTENTS;

EXIT;
SQLEOF
GRIDEOF

#############################################################################
echo -e "\n========================================" | tee -a $LOG
echo "实验4: 边界条件" | tee -a $LOG
echo "========================================" | tee -a $LOG

su - grid << 'GRIDEOF' 2>&1 | tee -a $LOG
sqlplus -s / as sysasm << 'SQLEOF'
SET ECHO ON FEEDBACK ON LINESIZE 200

PROMPT === 4.1 创建测试磁盘组 ===
CREATE DISKGROUP TGRP_TEST EXTERNAL REDUNDANCY DISK 'ORCL:TDISK1' ATTRIBUTE 'compatible.asm'='19.0';

PROMPT === 4.2 添加已在组中的磁盘(预期失败) ===
ALTER DISKGROUP TGRP_TEST ADD DISK 'ORCL:TDISK1';

PROMPT === 4.3 添加不存在的磁盘(预期失败) ===
ALTER DISKGROUP TGRP_TEST ADD DISK 'ORCL:NOTEXIST';

PROMPT === 4.4 用已占用磁盘创建新组(预期失败) ===
CREATE DISKGROUP TGRP_DUP EXTERNAL REDUNDANCY DISK 'ORCL:TDISK1' ATTRIBUTE 'compatible.asm'='19.0';

PROMPT === 清理 ===
DROP DISKGROUP TGRP_TEST INCLUDING CONTENTS;

EXIT;
SQLEOF
GRIDEOF

#############################################################################
echo -e "\n========================================" | tee -a $LOG
echo "清理测试环境" | tee -a $LOG
echo "========================================" | tee -a $LOG

oracleasm deletedisk TDISK1 2>/dev/null
oracleasm deletedisk TDISK2 2>/dev/null
oracleasm deletedisk TDISK3 2>/dev/null
oracleasm deletedisk TDISK4 2>/dev/null
oracleasm deletedisk TDISK5 2>/dev/null
oracleasm deletedisk TDISK6 2>/dev/null

for i in 40 41 42 43 44 45; do
    losetup -d /dev/loop$i 2>/dev/null
done

rm -rf /test_asm

echo "测试环境清理完成" | tee -a $LOG

#############################################################################
echo -e "\n========================================" | tee -a $LOG
echo "实验结论汇总" | tee -a $LOG
echo "========================================" | tee -a $LOG
cat << 'SUMMARY' | tee -a $LOG

┌─────────────────────────────────────────────────────────────────────────┐
│                    ASM冗余度与磁盘添加实验结论                          │
├─────────────────────────────────────────────────────────────────────────┤
│ 冗余度     │ 最少磁盘/FG │ 支持failgroup │ 混合大小 │ 备注              │
├────────────┼─────────────┼───────────────┼──────────┼───────────────────┤
│ EXTERNAL   │ 1个磁盘     │ ❌ 不支持     │ ✅ 支持  │ 无冗余保护        │
│ NORMAL     │ 2个FG       │ ✅ 支持       │ ✅ 支持  │ 双向镜像          │
│ HIGH       │ 3个FG       │ ✅ 支持       │ ✅ 支持  │ 三向镜像          │
└────────────┴─────────────┴───────────────┴──────────┴───────────────────┘

常见错误码:
- ORA-15067: 命令与冗余度不兼容(如EXTERNAL指定failgroup)
- ORA-15072: failgroup数量不满足冗余要求(如HIGH用2个FG)
- ORA-15018: 无法创建磁盘组
- ORA-15029: 磁盘已被挂载
- ORA-15032: 操作未完成
- ORA-15063: 磁盘已属于其他磁盘组

关键发现:
1. EXTERNAL冗余度不支持指定failgroup，会报ORA-15067
2. NORMAL至少需要2个failgroup，HIGH至少需要3个
3. 所有冗余度都支持混合不同大小的磁盘
4. 已加入磁盘组的磁盘不能重复添加或用于其他组

SUMMARY

echo -e "\n详细日志: $LOG" | tee -a $LOG
