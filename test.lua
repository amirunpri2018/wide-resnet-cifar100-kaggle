-- ************************************************************
-- Author : Bumsoo Kim, 2016
-- Github : https://github.com/meliketoy/wide-residual-network
--
-- Korea University, Data-Mining Lab
-- wide-residual-networks Torch implementation
--
-- Description : test.lua
-- The testing code for ensembling each datasets.
-- ***********************************************************

local optim = require 'optim'

local M = {}
local Tester = torch.class('resnet.Tester', M)
local csvigo = require 'csvigo'

-- Initialize training class
function Tester:__init(model_tensor, criterion, opt, optimState)
    self.model_tensor = model_tensor
    self.criterion = criterion
    self.optimState = optimState or {
        learningRate = opt.LR,
        learningRateDecay = 0.0,
        momentum = opt.momentum,
        nesterov = true,
        dampening = 0.0,
        weightDecay = opt.weightDecay,
    }
    self.opt = opt
end

-- Validation process
function Tester:test(epoch, dataloader)
    -- Computes the top N scores of the validation set
    local timer = torch.Timer()
    local dataTimer = torch.Timer()
    local size = dataloader:size()

    local top1Sum, top5Sum = 0.0, 0.0
    local N = 0

    -- Set the batch normalization to validation mode : moving average 0.9
    for i=1,self.opt.nEnsemble do
        self.model_tensor[i]:evaluate()
    end

    local final_result = torch.Tensor():long()
    local true_target = torch.Tensor():long()
    for n, sample in dataloader:run(self.opt.testOnly) do
        local dataTime = dataTimer:time().real

        -- Copy input and target into the GPUs
        self:copyInputs(sample)
        out = 0.0
        for i=1,self.opt.nEnsemble do
            result = self.model_tensor[i]:forward(self.input):float()
            if(self.opt.ensembleMode == 'avg') then
                tmp = result
                out = out+(tmp)
            elseif(self.opt.ensembleMode == 'max') then
                if(i==1) then out = result
                else out = torch.cmax(result, out) end
            elseif(self.opt.ensembleMode == 'min') then
                if(i==1) then out = result
                else out = torch.cmin(result, out) end
            end
        end

        -- print out progress bar
	-- xlua.progress(n, size)

        if(self.opt.ensembleMode == 'avg') then out = out/self.opt.nEnsemble end
        local output = out
        local batchSize = output:size(1)
        true_target = torch.cat(true_target, self.target:long(),1)
        local top1, top5 = self:computeScore(output, sample.target)
        top1Sum = top1Sum + top1*batchSize
        top5Sum = top5Sum + top5*batchSize
        N = N + batchSize

	local _ , predictions = output:float():sort(2, true) -- sort in descending orders
        final_result = torch.cat(final_result, predictions:narrow(2,1,1),1)
        timer:reset()
        dataTimer:reset()
    end
    final_result = final_result-1
    true_target = true_target-1
    local data_tobe_saved = {ids=torch.totable(torch.range(0,9999):view(-1)),labels=torch.totable(final_result:view(-1)),true_labels=torch.totable(true_target:view(-1))}
    csvigo.save{path='ensemble_' .. tostring(self.opt.nExperiment) .. '.csv',data=data_tobe_saved}
    return top1Sum/N, top5Sum/N
end

-- Scoring Process
function Tester:computeScore(output, target)
    -- Coputes the top1 and top5 error rate
    local batchSize = output:size(1)
    local _ , predictions = output:float():sort(2, true) -- sort in descending orders

    -- Find which predictions match the target
    local correct = predictions:eq(
        target:long():view(batchSize, 1):expandAs(output))

    -- Top-1 score
    local top1 = (correct:narrow(2, 1, 1):sum() / batchSize)

    -- Top-5 score, if there are at least 5 classes
    local len = math.min(5, correct:size(2))
    local top5 = (correct:narrow(2, 1, len):sum() / batchSize)

    return top1*100, top5*100
end

-- Copying Inputs into the GPUs
function Tester:copyInputs(sample)
    -- Copies the inputs into a CUDA tensor, if using 1 GPU, or to pinned memory
    -- If using DataParallelTable, the target is always copied to a CUDA tensor
    self.input = self.input or (self.opt.nGPU == 1 and torch.CudaTensor() or cutorch.createCudaHostTensor())
    self.target = self.target or torch.CudaTensor()
    self.input:resize(sample.input:size()):copy(sample.input)
    self.target:resize(sample.target:size()):copy(sample.target)
end

return M.Tester
