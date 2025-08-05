#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
import os

# 设置中文字体
plt.rcParams['font.sans-serif'] = ['SimHei', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False

def create_hct_plot(results_file):
    """创建握手完成时间图表"""
    # 读取数据，跳过注释行
    with open(results_file, 'r') as f:
        lines = f.readlines()
    
    # 找到实际数据开始的行
    data_lines = []
    for line in lines:
        if not line.startswith('#') and line.strip():
            data_lines.append(line.strip())
    
    if len(data_lines) < 2:
        print("没有足够的数据")
        return
    
    # 解析CSV数据
    header = data_lines[0].split(',')
    data_rows = []
    for line in data_lines[1:]:
        data_rows.append(line.split(','))
    
    df = pd.DataFrame(data_rows, columns=header)
    df['test_num'] = pd.to_numeric(df['test_num'])
    df['hct_ms'] = pd.to_numeric(df['hct_ms'])
    
    # 只使用成功的测试数据
    df_success = df[df['connection_status'] == 'SUCCESS'].copy()
    
    if df_success.empty:
        print("没有成功的测试数据")
        return
    
    # 计算统计数据
    mean_hct = df_success['hct_ms'].mean()
    std_hct = df_success['hct_ms'].std()
    min_hct = df_success['hct_ms'].min()
    max_hct = df_success['hct_ms'].max()
    
    # 创建图表
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))
    
    # 图1: 带误差棒的条形图
    ax1.bar(['平均握手完成时间'], [mean_hct], yerr=std_hct, 
            capsize=10, color='skyblue', edgecolor='navy', linewidth=2)
    ax1.set_ylabel('时间 (毫秒)', fontsize=12)
    ax1.set_title('strongSwan IPsec 握手完成时间 (HCT) - 理想网络条件', fontsize=14, fontweight='bold')
    ax1.grid(True, alpha=0.3)
    
    # 在条形图上添加数值标签
    ax1.text(0, mean_hct + std_hct + 1, f'{mean_hct:.2f}±{std_hct:.2f}ms', 
             ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    # 添加统计信息
    stats_text = f'测试次数: {len(df_success)}\n最小值: {min_hct:.2f}ms\n最大值: {max_hct:.2f}ms'
    ax1.text(0.02, 0.98, stats_text, transform=ax1.transAxes, 
             verticalalignment='top', bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8))
    
    # 图2: 时间序列图
    ax2.plot(df_success['test_num'], df_success['hct_ms'], 'o-', color='red', alpha=0.7, linewidth=1)
    ax2.axhline(y=mean_hct, color='blue', linestyle='--', label=f'平均值: {mean_hct:.2f}ms')
    ax2.fill_between(df_success['test_num'], mean_hct - std_hct, mean_hct + std_hct, 
                     alpha=0.2, color='blue', label=f'±1σ: {std_hct:.2f}ms')
    ax2.set_xlabel('测试序号', fontsize=12)
    ax2.set_ylabel('握手完成时间 (毫秒)', fontsize=12)
    ax2.set_title('握手完成时间变化趋势', fontsize=14, fontweight='bold')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    # 保存图表
    plot_filename = f'ipsec_hct_plot_{pd.Timestamp.now().strftime("%Y%m%d_%H%M%S")}.png'
    plt.savefig(plot_filename, dpi=300, bbox_inches='tight')
    print(f"图表已保存为: {plot_filename}")
    
    # 显示图表
    plt.show()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法: python3 generate_plot.py <results_file>")
        sys.exit(1)
    
    results_file = sys.argv[1]
    if not os.path.exists(results_file):
        print(f"错误: 文件 {results_file} 不存在")
        sys.exit(1)
    
    create_hct_plot(results_file)
