-- Find bank components directly by their named component IDs.

local BankInterface = {}

BankInterface.ITEMS = id.Component.BANK__BANK_INV
BankInterface.ITEMS_CONTAINER = id.Component.BANK__BANK_ITEMS_CONTAINER

function BankInterface.Get(componentID)
    return ui.Interfaces:GetComponent(componentID)
end

-- Missing or unreadable controls return nil.
function BankInterface.Find(componentID)
    local ok, value = pcall(BankInterface.Get, componentID)
    return ok and value or nil
end

return BankInterface
