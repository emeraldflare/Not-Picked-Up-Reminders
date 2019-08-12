local settings = {};
settings.EmailArticle = GetSetting("EmailArticle");
settings.EmailLoan = GetSetting("EmailLoan");
settings.Exclusions = GetSetting("Exclusions");

function Init()
	RegisterSystemEventHandler("SystemTimerElapsed", "ConditionalNotifications");
end

function ConditionalNotifications()	
	local query = "SELECT Subject FROM NotificationTemplates WHERE Name = '" .. settings.EmailArticle .. "'";
	local artsub = Silence(PullScalar(query)):gsub("<#.->", "%%%%%*"); -- Replaces notification template tags with wildcards.
	if not artsub then
		return;
	end
	
	query = "SELECT Subject FROM NotificationTemplates WHERE Name = '" .. settings.EmailLoan .. "'";
	local loansub = Silence(PullScalar(query)):gsub("<#.->", ".*");
	if not loansub then
		return;
	end
	
	query = "SELECT Transactions.TransactionNumber, Transactions.RequestType FROM Transactions INNER JOIN History ON Transactions.TransactionNumber = History.TransactionNumber INNER JOIN Users ON Transactions.Username = Users.Username WHERE TransactionStatus = 'Request Conditionalized' AND Entry LIKE 'Updated on OCLC as Conditional%'"; 
	
	if settings.Exclusions:match("%a") then
		query = query .. " AND NVTGC NOT IN (" .. settings.Exclusions .. ")";
	end
	
	local results = PullData(query);
	if not results then
		return;
	end

	for ct = 0, results.Rows.Count - 1 do
		local tn = results.Rows:get_Item(ct):get_Item("TransactionNumber");
		local reqtype = results.Rows:get_Item(ct):get_Item("RequestType");

		local query = "SELECT Subject FROM EMailCopies WHERE TransactionNumber = '" .. tn .. "'"; -- For some reason I can't join this into the initial query in a way that works, so this is sadly necessary.
		local subresults = PullData(query);

		local submatch = false;
		for dt = 0, subresults.Rows.Count - 1 do
			local subject = subresults.Rows:get_Item(dt):get_Item("Subject");
			if subject:match(artsub) or subject:match(loansub) then
				submatch = true;
			end
		end
			
		if not submatch or subresults.Rows.Count == 0 then
			SendNotification(tn, reqtype);
		end
	end
end

function SendNotification(tn, reqtype)
	if reqtype == "Article" then
		ExecuteCommand("SendTransactionNotification", {tn, settings.EmailArticle});
	elseif reqtype == "Loan" then
		ExecuteCommand("SendTransactionNotification", {tn, settings.EmailLoan});
	end
end

function Silence(str, un) -- Allows variables with Lua magic characters to be used as a matchstring. First argument is the variable to be used as the matchstring. Second (optional) argument reverses the process, usually for the sake of readability.

	if un ~= "un" then -- Silence.
		str = str:gsub("%%", "%%%%"):gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%.", "%%."):gsub("%+", "%%+"):gsub("%-", "%%-"):gsub("%*", "%%*"):gsub("%?", "%%?"):gsub("%[", "%%["):gsub("%^", "%%^"):gsub("%$", "%%$");
	else -- Un-Silence.
		str = str:gsub("%%%(", "("):gsub("%%%)", ")"):gsub("%%%.", "."):gsub("%%%+", "+"):gsub("%%%-", "-"):gsub("%%%*", "*"):gsub("%%%?", "?"):gsub("%%%[", "["):gsub("%%%^", "^"):gsub("%%%$", "$"):gsub("%%%%", "%");
	end
	
	return str;
end

function PullData(query) -- Used for SQL queries that will return more than one result.
	local connection = CreateManagedDatabaseConnection();
	function PullData2()
		connection.QueryString = query;
		connection:Connect();
		local results = connection:Execute();
		connection:Disconnect();
		connection:Dispose();
		
		return results;
	end
	
	local success, results = pcall(PullData2, query);
	if not success then
		LogDebug("Problem with SQL query: " .. query .. "\nError: " .. tostring(results));
		connection:Disconnect();
		connection:Dispose();
		return false;
	end
	
	return results;
end

function PullScalar(query) -- Used for SQL queries that will only return one result.
	local connection = CreateManagedDatabaseConnection();
	function PullScalar2()
		connection.QueryString = query;
		connection:Connect();
		local results = connection:ExecuteScalar();
		connection:Disconnect();
		connection:Dispose();
		
		return results;
	end
	
	local success, results = pcall(PullScalar2, query);
	if not success then
		LogDebug("Problem with SQL query for scalar: " .. query .. "\nError: " .. tostring(results));
		connection:Disconnect();
		connection:Dispose();
		return false;
	end
	
	return results;
end

function OnError(errorArgs)
	LogDebug("Oh no! Conditional Notifications had a problem! Error: " .. tostring(errorArgs));
end

