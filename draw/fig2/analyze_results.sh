#!/bin/bash

# 分析突发丢包率测试结果脚本

RESULTS_FILE="burst_loss_results_20250719_141224/burst_loss_results.csv"
OUTPUT_FILE="burst_loss_results_20250719_141224/corrected_summary.csv"

echo "# 突发丢包率测试汇总统计 (修正版)"
echo "# 适用于生成图5和图6"
echo "# 丢包率(%),成功率(%),HCT均值(s),HCT中位数(s),HCT标准差(s),平均重传次数" > "$OUTPUT_FILE"

# 分析每个丢包率
for loss_rate in 0 5 10 15; do
    echo "分析丢包率 ${loss_rate}%..."
    
    # 提取该丢包率的所有成功连接数据
    success_data=$(grep "^${loss_rate}," "$RESULTS_FILE" | awk -F',' '$3==1 {print $4}')
    retrans_data=$(grep "^${loss_rate}," "$RESULTS_FILE" | awk -F',' '$3==1 {print $5}')
    
    # 计算基本统计
    total_tests=$(grep "^${loss_rate}," "$RESULTS_FILE" | wc -l)
    success_count=$(echo "$success_data" | wc -l)
    
    if [[ $total_tests -gt 0 ]]; then
        success_rate=$(echo "scale=2; $success_count * 100 / $total_tests" | bc)
    else
        success_rate=0
    fi
    
    echo "  总测试数: $total_tests"
    echo "  成功数: $success_count"
    echo "  成功率: ${success_rate}%"
    
    if [[ $success_count -gt 0 ]]; then
        # 计算HCT统计
        hct_mean=$(echo "$success_data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.3f", sum/count; else print "0"}')
        hct_median=$(echo "$success_data" | sort -n | awk '{values[NR]=$1} END {n=NR; if(n%2==1) print values[(n+1)/2]; else printf "%.3f", (values[n/2]+values[n/2+1])/2}')
        hct_min=$(echo "$success_data" | sort -n | head -1)
        hct_max=$(echo "$success_data" | sort -n | tail -1)
        hct_std=$(echo "$success_data" | awk -v mean="$hct_mean" '{sum+=($1-mean)^2; count++} END {if(count>1) printf "%.3f", sqrt(sum/(count-1)); else print "0"}')
        
        # 计算重传统计
        retrans_mean=$(echo "$retrans_data" | awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}')
        retrans_max=$(echo "$retrans_data" | sort -n | tail -1)
        
        echo "  HCT均值: ${hct_mean}s"
        echo "  HCT中位数: ${hct_median}s"
        echo "  HCT标准差: ${hct_std}s"
        echo "  HCT范围: ${hct_min}s - ${hct_max}s"
        echo "  平均重传: ${retrans_mean}"
        echo "  最大重传: ${retrans_max}"
        
        # 输出到CSV
        echo "${loss_rate},${success_rate},${hct_mean},${hct_median},${hct_std},${retrans_mean}" >> "$OUTPUT_FILE"
    else
        echo "  无成功连接"
        echo "${loss_rate},0,0,0,0,0" >> "$OUTPUT_FILE"
    fi
    
    echo ""
done

echo "修正版汇总统计已保存到: $OUTPUT_FILE"

# 生成箱形图数据
BOXPLOT_FILE="burst_loss_results_20250719_141224/corrected_boxplot_data.csv"
echo "# 握手完成时间箱形图数据" > "$BOXPLOT_FILE"
echo "# 用于生成图6: HCT vs 突发丢包率的箱形图" >> "$BOXPLOT_FILE"
echo "# 丢包率(%),HCT(s)" >> "$BOXPLOT_FILE"

for loss_rate in 0 5 10 15; do
    success_data=$(grep "^${loss_rate}," "$RESULTS_FILE" | awk -F',' '$3==1 {print $4}')
    if [[ -n "$success_data" ]]; then
        echo "$success_data" | while read hct; do
            echo "${loss_rate},${hct}" >> "$BOXPLOT_FILE"
        done
    fi
done

echo "修正版箱形图数据已保存到: $BOXPLOT_FILE" 