#!/bin/bash
export netType='wide-resnet'
export depth=28
export width=10
export dataset='cifar100'
export experiment_number=1
mkdir -p modelState

th main.lua \
    -dataset ${dataset} \
    -netType ${netType} \
    -top5_display true \
    -testOnly false \
    -dropout 0.3 \
    -batchSize 128 \
    -depth ${depth} \
    -widen_factor ${width} \
    -nExperiment ${experiment_number} \
    | tee logs/${dataset}/${netType}-${depth}x${width}/log_${experiment_number}.txt

