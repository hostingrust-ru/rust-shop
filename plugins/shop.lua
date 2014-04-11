--[[
	© 2014 HostingRust.ru
	Plugin for implementation the web-api requests for service: shop.hostingrust.ru
--]]

-- Be safe, your config :)
local MARKET_ID  = 0;
local SECRET_KEY = 'YOUR SECRET_KEY';

-- DO NOT EDIT BELOW THIS LINE
PLUGIN.Title = "Shop System";
PLUGIN.Description = "The shop system for human";
PLUGIN.Author = "Andrew Mensky";
PLUGIN.Version = "Git";

local AUTH_TIME   = 0;
local EXPIRES_IN  = 0;
local MARKET_NAME = "";

-- Exend standart stl
function util.PrintTable(t, indent, done)
	done = done or {};
	indent = indent or 0;

	for key, value in pairs (t) do
		if  (type(value) == "table" and not done[value]) then
			done [value] = true;
			print(string.rep("\t", indent) .. tostring(key) .. ":");
			util.PrintTable (value, indent + 2, done);
		else
			print(string.rep("\t", indent) .. tostring (key) .. " = " .. tostring(value));
		end;
	end;
end;

function table.HasValue(t, val)
	for k,v in pairs(t) do
		if (v == val) then return true end;
	end;
	return false;
end;

function table.count(t)
	local i = 0;
	for k in pairs(t) do i = i + 1 end;
	return i;
end;

local function implode(tbl, seperator)
	local str = "";
	local b = true;

	for k, v in pairs(tbl) do
		str = str..(b and "" or seperator)..tostring(k).."="..tostring(v);
		b = false; 
	end;

	return str;
end;

-- A function to get curtime of server
local curTime = util.GetStaticPropertyGetter(UnityEngine.Time, "realtimeSinceStartup");

-- A function call when plugin initialized
function PLUGIN:Init()
	print("SHOP plugin loading...");

	self.version      = 0.13;
	self.initialized  = false;
	self.on_auth      = false;
	self.fatal_errors = {3, 5, 6, 7, 8, 9};

	self:LoadConfig();
	self:AddUserCommand("shop_sell", self.cmdSell);
	self:AddUserCommand("shop_buy", self.cmdBuy);
	self:AddUserCommand("shop_cash", self.cmdCash);

	self:AddAdminCommand("shop_import", self.cmdImport);
	self:AddAdminCommand("shop_auth", self.cmdAuth);
	self:AddAdminCommand("shop_key", self.cmdKey);

	self.re_auth_timer = timer.Once(10, function() self:Auth(true); end);
end;

-- A function call when plugin has been reload
function PLUGIN:Unload()
	if (self.re_auth_timer) then self.re_auth_timer:Destroy(); end;
end;

-- A function to add admin chat command
function PLUGIN:AddAdminCommand(name, callback)
	local func = function(class, netuser, cmd, args)
		-- Check admin permision
		if (not netuser:CanAdmin()) then
			rust.Notice(netuser, "Unknown chat command!");
			return false;
		end;

		return callback(class, netuser, cmd, args);
	end;

	self:AddChatCommand(name, func);
end;

-- A function to add shop chat command
function PLUGIN:AddUserCommand(name, callback)
	local func = function(class, netuser, cmd, args)
		-- Check initialized shop status
		if (not class.initialized) then
			class:chat(netuser, "Магазин не инициализирован.");
			return false;
		end;

		return callback(class, netuser, cmd, args); 
	end;

	self:AddChatCommand(name, func);
end;

-- A function to load config of this plugin
function PLUGIN:LoadConfig()
	local b, res = config.Read("shop");
	self.Config  = res or {};

	self:InitConfig("shop_url", "");
	self:InitConfig("api_url", "http://shop.hostingrust.ru/api");
	self:InitConfig("sell_slot", 30);
	self:InitConfig("debug", true);
	self:InitConfig("black_list", {-971007166});
	self:InitConfig("black_as_white", false);
	self:InitConfig("require_recovery", {});

	config.Save("shop");
end;

-- A function to get config with default value
function PLUGIN:InitConfig(name, default)
	if (type(self.Config) ~= "table") then
		self.Config = {};
	end;

	if (self.Config[name] == nil or type(self.Config[name]) ~= type(default)) then
		self.Config[name] = default;
	end;
end;

-- A function to send msg to the player with shop tag
function PLUGIN:chat(netuser, msg)
	if (not netuser) then return; end;
	rust.SendChatToUser(netuser, "shop", tostring(msg));
end;

-- A function to debug message
function PLUGIN:debug(msg, global)
	if (self.Config.debug) then
		if (global) then
			self:log(msg);
		else
			print("SHOP: "..tostring(msg));
		end;
	end;
end;

-- A function to pint msg for all admin on server
function PLUGIN:log(msg)
	print("SHOP: "..tostring(msg));

	local plys = rust.GetAllNetUsers();

	for i=1, #plys do
		if (plys[i]:CanAdmin()) then
			rust.SendChatToUser(plys[i], "shop", tostring(msg));
		end;
	end;
end;

-- A function to call web shop api
function PLUGIN:CallApi(api_method, data, onSuccess, onFailure)
	-- Validate data
	if (not api_method or type(api_method) ~= "string") then
		return false, "API method not valid!";
	elseif (onSuccess and type(onSuccess) ~= "function") then
		return false, "onSuccess not valid!";
	elseif (onFailure and type(onFailure) ~= "function") then
		return false, "onFailure not valid!";
	end;

	data = type(data) ~= "table" and {} or data;

	-- Prepare data
	local api_url   = self.Config.api_url.."/"..api_method;
	local post_data = data.post and implode(data.post, "&") or "";
	local get_data = {};

	if (data.get) then
		get_data = data.get;
	elseif (not data.post and table.count(data) > 0) then
		get_data = data;
	end;

	get_data.token      = api_method ~= "global.auth" and TOKEN or nil;
	get_data.secret_key = api_method == "global.auth" and SECRET_KEY or nil;
	get_data.market_id  = api_method == "global.auth" and MARKET_ID or nil;
	api_url             = api_url.."?"..implode(get_data, "&");

	self:debug(api_url);

	-- Create web request
	webrequest.PostQueue(api_url, post_data, function(_, code, response)
		-- Check http status
		if (code ~= 200) then
			local err_msg = "Error on the server, returned code: "..tostring(code);
			if (onFailure) then onFailure(err_msg, 0) end;
			error("SHOP: "..err_msg);
			return false;
		end;

		-- Decode and validate json response
		local result = json.decode(response);

		if (type(result) ~= "table") then
			local err_msg = "Server return incorrect json response.";
			if (onFailure) then onFailure(err_msg, 0) end;
			error("SHOP: "..err_msg);
			return false;
		elseif (result.plugin_version and result.plugin_version > self.version) then
			self:log("New plugin version available, keep calm and make update.");
		end;

		-- Switch correct json result
		if (not result.error and onSuccess) then
			onSuccess(result.response);
		elseif (onFailure) then
			-- De initialize
			if (table.HasValue(self.fatal_errors, result.error_code)) then
				self.initialized = false;
			end;

			onFailure(result.error, result.error_code or 1);
		end;
	end);
end;

function PLUGIN:Auth(bRetry)
	-- Check auth thered exists
	if (self.on_auth) then return false; end;
	self.on_auth = true;

	-- Call API
	self:CallApi("global.auth", {}, function(response)
		-- Initialize shop
		TOKEN, AUTH_TIME, EXPIRES_IN, MARKET_NAME = response.token, response.auth_time, response.expires_in-10, response.market_name;
		self.initialized = true;
		self.on_auth = false;

		-- Create re-auth timer
		if (self.re_auth_timer) then self.re_auth_timer:Destroy(); end;

		self.re_auth_timer = timer.Once(EXPIRES_IN, function()
			self:Auth(true);
		end);

		self:log("Auth complete ["..MARKET_NAME.."].");
		self:log("Re-Auth will be called after "..EXPIRES_IN..' sec.');

	end, function(err, error_code)
		-- Clear data
		TOKEN, AUTH_TIME, MARKET_NAME = '', 0, '';
		self.initialized = false;
		self.on_auth = false;
		self:log("Error web API auth ["..error_code.."]: "..err);

		-- Make retry
		if (bRetry) then
			if (table.HasValue(self.fatal_errors, result.error_code)) then
				self:log("Automatic retry auth cannot be execute, fatal error.");
			else
				self.on_auth = true;
				self:log("Execute retry auth.");
				self.re_auth_timer = timer.Once(10, function()
					self.on_auth = false;
					if (not self.initialize) then self:Auth(true); end;
				end);
			end;
		end;
	end);

	return true;
end;

-- Getter functions
function PLUGIN:GetMarketName() return MARKET_NAME; end;
function PLUGIN:IsInitialized() return self.initialize; end;
function PLUGIN:GetMarketID() return MARKET_ID; end;
function PLUGIN:GetConfig() return self.Config; end;

-- A function to import rust items (only admin service)
function PLUGIN:cmdImport(netuser, cmd, args)
	-- Prepare data
	local count = Rust.DatablockDictionary.All.Length;
	local list = {};

	for i=0, count-1 do
		local item = Rust.DatablockDictionary.All[i];
		local cat = tostring(item.category);
		local s = string.find(cat, ": ");
		local l = string.len(cat);
		cat = string.sub(cat, s+2, l);

		list[ tonumber(item.uniqueID) ] = {
			name       = tostring(item.name),
			cat        = tonumber(cat),
			icon       = string.gsub(item.icon, "content/item/tex/", ""),
			desc       = tostring(item:GetItemDescription()),
			splittable = item:IsSplittable();
		};
	end;

	local data = json.encode(list);

	-- Call API
	self:log("Starting import "..tostring(count).." items!");

	self:CallApi("ritem.import", { post = { data = data } }, function(response)
		self:log("Import items success!");
	end, function(err)
		self:log("Error import items ["..err.."]!");
	end);
end;

function PLUGIN:cmdAuth(netuser, cmd, args)
	-- Call Auth function
	if (not self:Auth()) then
		self:chat(netuser, "Auth thered allready execute.");
	end;
end;

function PLUGIN:cmdKey(netuser, cmd, args)
	-- Check admin permision
	if (not netuser:CanAdmin()) then
		rust.Notice(netuser, "Unknown chat command!");
		return false;
	end;

	if (not args[1]) then return false end;

	SECRET_KEY = args[1];
	self:log("Secret key has ben changed, don't forget change him in script MANUALITY!");
end;

function PLUGIN:modsList(item)
	local t = {};

	if (type(item.itemMods) ~= "string" and item.usedModSlots > 0) then
		for i=0, item.usedModSlots-1 do
			table.insert(t, item.itemMods[i].uniqueID);
		end;
	end;

	return t;
end;

-- A function return count of free slout in player inventory
function PLUGIN:FreeSlotsCount(netuser)
	local inv = rust.GetInventory(netuser);
	local count = 0;

	if (not inv) then return 0; end;

	for i=0, 35 do
		if (inv:IsSlotFree(i)) then
			count = count + 1;
		end;
	end;

	return count;
end;

-- A function to give item with some parameters
function PLUGIN:GiveItem(netuser, uid, dt)
	-- Initialize data
	local datablock = Rust.DatablockDictionary.GetByUniqueID(uid);
	local inv = rust.GetInventory(netuser);
	dt = dt or {};

	-- Validate data
	if (not datablock) then
		return false, "Datablock not find.";
	elseif (not inv) then
		return false, "Player inventory not found.";
	elseif (self:FreeSlotsCount(netuser) <= 0) then
		return false, "Has no empty slots.";
	end;

	-- Give player item
	local item = inv:AddItemSomehow(datablock, InventorySlotKind.Belt, 0, tonumber(dt.uses) or 1);
	if (not item) then return false, "Failed to add item."; end;

	-- Set item properties
	item:SetCondition(tonumber(dt.condition) or 1.0);
	item:SetMaxCondition(tonumber(dt.maxcondition) or 1.0);

	-- Addition mods
	if (type(item.itemMods) ~= "string") then
		item:SetTotalModSlotCount(tonumber(dt.modSlots) or 0);

		if (type(dt.itemMods) == "table") then
			for i = 1, #dt.itemMods do
				local mod = Rust.DatablockDictionary.GetByUniqueID(dt.itemMods[i]);
				
				if (mod and type(mod.modFlag) ~= "string") then
					item:AddMod(mod);
				else
					inv:RemoveItem(item); -- Take item
					return false, "Invalid mod item ["..dt.itemMods[i].."].";
				end;
			end;
		end;
	end;

	return item, '';
end;

function PLUGIN:cmdBuy(netuser, cmd, args)
	-- Initializing data
	local barcode = tonumber(args[1]);

	-- Validate data
	if (not barcode) then
		self:chat(netuser, "Пожалуйста, укажите код вещи.");
		return false;
	end;

	if (self:FreeSlotsCount(netuser) <= 0) then
		self:chat(netuser, "У вас нет свободных слотов для покупки.");
		return false;
	end;

	-- Call hook
	if (plugins.Call("PreCanBuyItem", netuser, barcode) == false) then return false; end;

	-- Call API
	self:chat(netuser, "Барыга пытается найти ваш товар!");

	self:CallApi("item.getById", { id = barcode, filter = json.encode({ sold = false }) }, function(response)
		local item = response[1];

		if (not item) then
			self:chat(netuser, "Барыга не нашел товар, скорей всего уже продан!");
			return false;
		end;

		-- Call hook
		if (plugins.Call("CanBuyItem", netuser, item) == false) then return false; end;

		-- Call API
		local properties = { sold = true };
		self:CallApi("item.edit", { id = barcode, properties = json.encode(properties) }, function(response)
			-- Checking changes
			 if (not response.sold) then
			 	return self:chat(netuser, "Товар уже продан!");
			 end;

			-- Give item
			local success, err = self:GiveItem(netuser, tonumber(item.item_id), {
				uses         = item.uses,
				condition    = item.condition,
				maxcondition = item.maxcondition,
				modSlots     = item.mod_slots,
				itemMods     = item.item_mods or {},
			});

			if (success) then
				plugins.Call("OnBuyItem", netuser, item);
				self:chat(netuser, "Барыга продал вам товар!");
			else
				self.Config.require_recovery[barcode] = { sold = false };
				config.Save("shop");

				self:chat(netuser, "Барыга передумал: "..err);
			end;
		end, function(err)
			self:chat(netuser, "Барыга не продаст вам товар: "..err);
		end);
	end, function(err)
		self:chat(netuser, "Барыга не нашел товар: "..err);
	end);
end;

function PLUGIN:cmdSell(netuser, cmd, args)
	-- Call hook
	if (plugins.Call("PreCanSellItem", netuser) == false) then return false; end;

	-- Initializing data
	local price = args[1] and tonumber(args[1]) or 0;
	local uid   = rust.GetUserID(netuser);
	local name  = netuser.displayName;
	local inv   = rust.GetInventory(netuser);
	local item;

	-- Validate data
	if (price <= 0) then
		self:chat(netuser, "Не корректная цена!");
		return false;
	end;

	if (not inv) then
		self:chat(netuser, "Инвентарь не инициализирован!");
		return false;
	else
		local b, i = inv:GetItem(self.Config.sell_slot);

		if (not b) then
			self:chat(netuser, "Для продажи, поместите вещь на "..(self.Config.sell_slot-29).."-й слот быстрого доступа!");
			return false;
		end;

		item = i;
	end;

	-- Generate api data
	local item_mods = self:modsList(item);
	local data = {
		item_id       = item.datablock.uniqueID,
		price         = price,
		uses          = tonumber(item.uses) or 1,
		condition     = item.condition or 1.0,
		maxcondition  = item.maxcondition or 1.0,
		mod_slots     = tonumber(item.totalModSlots) or 0,
		item_mods     = json.encode(item_mods),
		owner_id      = uid,
		owner_name    = name,
		auction       = false,
	};

	-- Call hook
	if (plugins.Call("CanSellItem", netuser, data) == false) then return false; end;

	-- Take item and log hee
	inv:RemoveItem(self.Config.sell_slot);
	self:debug("Take item["..item.datablock.uniqueID.."]["..item.datablock.name.."] from '"..name.."' with: { uses: "..item.uses..", condition: "..item.condition.."/"..item.maxcondition..", mods: "..data.item_mods.." }");
	self:chat(netuser, "Барыга взял вашу вещь на осмотр!");

	-- Call API
	self:CallApi("item.add", data, function(response)
		plugins.Call("OnSellItem", netuser, data);

		self:chat(netuser, "Барыга принял вашу вещь на продажу!");
		self:chat(netuser, "Код вещи: "..response.barcode);
	end, function(err)
		local item = self:GiveItem(netuser, data.item_id, {
			uses         = data.uses,
			condition    = data.condition,
			maxcondition = data.maxcondition,
			modSlots     = data.mod_slots,
			itemMods     = item_mods
		});

		self:chat(netuser, "Барыга вернул ваш хлам: "..err);
	end);
end;

function PLUGIN:cmdCash(netuser, cmd, args)
	-- Custom checker
	if (plugins.Call("CanGetCash", netuser) == false) then return false; end;

	self:chat(netuser, "Барыга проверяет записи ваших продаж!");

	local uid = rust.GetUserID(netuser);
	local data = {
		id = uid,
		filter = json.encode({sold = true})
	};

	self:CallApi("item.getByOwnerId", data, function(response)
		local cash = 0;
		local count = #response;

		for i=1, count do
			cash = cash + response[i].price;
		end;

		if (cash <= 0) then
			self:chat(netuser, "Ваше барахло никто не купил.");
			return false;
		end;

		plugins.Call("OnGetCash", netuser, count, cash, response);
	end, function(err)
		self:chat(netuser, "Барыга нашел ошибку: "..err);
	end);
end;

-- Events
function PLUGIN:CanBuyItem(netuser, item)
	-- Backlist check
	local exist = table.HasValue(self.Config.black_list, item.item_id);

	if ((exist and not self.Config.black_as_white) or (not exist and self.Config.black_as_white)) then
		self:chat(netuser, "Покупка этого предмета запрещена администратором.");
		return false;
	end;

	-- Money check
	local econmod = plugins.Find("econ");
	
	if (econmod) then
		if (econmod:getMoney(netuser) < item.price) then
			self:chat(netuser, "Барыга огорчен, недостаточно средств.");
			return false;
		end;
	end;
end;

function PLUGIN:OnBuyItem(netuser, item)
	local econmod = plugins.Find("econ");

	if (econmod) then
		econmod:takeMoneyFrom(netuser, item.price);
		econmod:printmoney(netuser);
	end;
end;

function PLUGIN:CanSellItem(netuser, item)
	local exist = table.HasValue(self.Config.black_list, item.item_id);

	if ((exist and not self.Config.black_as_white) or (not exist and self.Config.black_as_white)) then
		self:chat(netuser, "Продажа этого предмета запрещена администратором.");
		return false;
	end;
end;

function PLUGIN:OnGetCash(netuser, count, cash, items)
	local econmod = plugins.Find("econ");

	if (econmod) then
		local remove_list = {}

		for i=1, count do
			remove_list[i] = items[i].barcode;
		end;

		self:CallApi("item.remove", {list = json.encode(remove_list)}, function(response)
			econmod:giveMoneyTo(netuser, cash);
			self:chat(netuser, "Кол-во продаж: "..count);
			self:chat(netuser, "Общая сумма дохода: "..cash);
		end, function(err)
			self:chat(netuser, "Барыга нашел ошибку: "..err);
		end);
	end;
end;

-- Help
function PLUGIN:SendHelpText(netuser)
	self:chat(netuser, "Адрес онлайн магазина: "..self.Config.shop_url);
	self:chat(netuser, "/shop_buy <код> - для покупки вещей.");
	self:chat(netuser, "/shop_sell <цена> - для продажи, предварительно поместите вещь на "..(self.Config.sell_slot-29).."-й быстрого доступа.");
	self:chat(netuser, "/shop_cash - для получения средств с продаж.");
end;

-- Registration API
if (not api.Exists("shop")) then
	api.Bind(PLUGIN, "shop");
end;