-- ** WebRequest Queue Plugin ** --
-- ***************************** --
-- ********* By UniOn ********** --

-- Plugin variables
PLUGIN.Title = "WebRequestQueue"
PLUGIN.Description = "WebRequest Queue Plugin"
PLUGIN.Author = "UniOn"
PLUGIN.Version = "0.21"

-- Global WebRequest queue function
function webrequest.SendQueue( url, func, ... )
	-- Get this plugin
	local this = plugins.Find( "queue" )

	-- Return if function doesn't exist
	if not ( func ) or not ( type( func ) == "function" ) then 
		return false, "Function not found" 
	end

	-- Add item to the queue
	return this:QueueAdd( url, false, func, ... )
end

-- Global Post WebRequest queue function
function webrequest.PostQueue( url, postData, func, ... )
	-- Get this plugin
	local this = plugins.Find( "queue" )

	-- Check for the post data
	if not ( postData ) then
		return false, "Post data not found"
	end

	-- Return if function doesn't exist
	if not ( func ) or not ( type( func ) == "function" ) then 
		return false, "Function not found" 
	end

	-- Add item to the queue
	return this:QueueAdd( url, postData, func, ... )
end

-- Init function
function PLUGIN:Init()
	-- Let the console now we're loading
	print ( "Loading Queue Resource...")

	-- Queue table and amount of items currently being requested
	self.Queue = {}
	self.Working = 0
	self.MaxQueue = 3
end

-- Add a new item to the queue
function PLUGIN:QueueAdd( pUrl, pData, pFunction, ... )
	-- Errrrrything alright?
	if not ( pUrl ) or not ( pFunction ) then return false end

	-- Add a new row to the table
	table.insert( self.Queue, 
		{
			url 	= pUrl,
			post    = pData,
			func 	= pFunction,
			args 	= {...}
		}
	)

	-- Oxide only handles 3 requests at once, so we don't want to load more than 3
	if ( self.Working < self.MaxQueue ) then self:QueueNext() return true, "Sent" end

	-- Return
	return true, "Queued"
end

-- Send out the next request, if not already 3 working
function PLUGIN:QueueNext()
	if ( #self.Queue > 0 ) and ( self.Queue[ 1 ] ) and ( self.Working < self.MaxQueue ) then
		k = self.Queue[ 1 ]
		table.remove( self.Queue, 1 )
		if ( k.post ) then
			result = webrequest.Post( k.url, k.post, function ( responseCode, result ) self:QueueCallBack( responseCode, result, k ) end )
		else
			result = webrequest.Send( k.url, function ( responseCode, result ) self:QueueCallBack( responseCode, result, k ) end )
		end
		if not ( result ) then return result end
		self.Working = self.Working + 1
		return result
	end

	-- Return
	return false
end

-- Callback function for all the queued requests
function PLUGIN:QueueCallBack( responseCode, result, tbl )
	-- Do we have the stuff we want?
	local b, res = pcall( function()
		if ( tbl ) then
			-- Call the function and the hook
			if ( tbl.args ) then
				tbl.func( false, responseCode, result, table.unpack( tbl.args ) )
				plugins.Call( "OnWebRequestFinish", responseCode, result, table.unpack( tbl.args ) )
			else
				tbl.func( false, responseCode, result )
				plugins.Call( "OnWebRequestFinish", responseCode, result )
			end
		end
	end);

	if ( not b ) then print( res ); end;

	-- Amount of calls still going on
	if ( self.Working > 1 ) then self.Working = self.Working - 1 else self.Working = 0 end

	-- Check if there's more waiting
	self:QueueNext()
end