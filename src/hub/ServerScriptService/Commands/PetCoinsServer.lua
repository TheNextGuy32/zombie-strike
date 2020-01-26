local ServerScriptService = game:GetService("ServerScriptService")

local DataStore2 = require(ServerScriptService.Vendor.DataStore2)

return function(context, coins, player)
	local player = player or context.Executor
	DataStore2("PetCoins", player):Increment(coins)
end