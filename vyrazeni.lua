local function load_tsv(filename)
  local data = {}
  local header = {}
  local f,msg = io.open(filename, "r")
  if not f then return nil, msg end
  local first = true
  for line in f:lines() do
    local items = {}
    for item in line:gmatch("([^\t]*)") do
      items[#items+1] = item
    end
    if first then
      header = items
    else
      data[#data+1] = items
    end
    first = false
  end
  return data, header
end

local function hash_by_field(table, field)
  local t = {}
  for _,v in pairs(table) do
    local key = v[field]
    t[key] = v
  end
  return t
end

local function check_duplicates(data)
  -- zkontroluj, jestli jednotky s duplicitímnázvem mají stejnej začátek signatury
  local main_signature 
  for _, record in ipairs(data) do
    -- zkoumáme jen první číslo v signatuře, můžou se lišit číslem za lomítkem nebo písmenkem
    local current_signature = record[6]:match("(%d+)")
    main_signature = main_signature or current_signature
    if main_signature ~= current_signature then return true end
  end
  return false
end

local function find_duplicates(data)
  local used = {}
  for k,v in ipairs(data) do
    local name = v[5]
    local count = used[name] or {}
    v.id = k
    table.insert(count, v)
    used[name] = count
  end

  for name, count in pairs(used) do
    if #count > 1 then
      if check_duplicates(count) then
        -- setřídit podle přírustkovýho čísla sestupně, nejnovější chceme nechat
        table.sort(count, function(a,b)
          return tonumber(a[1]) > tonumber(b[1])
        end)
        -- nastavit duplikáty jen pro starší jednotky
        for i = 2, #count do
          local record = count[i]
          data[record.id].duplicate = true
        end
      end
    end
  end

end

local function get_score(record, is_duplicate, loans)
  -- code
  local ck = record[1]
  -- po roce 2000 jsou čárový kódy 2592YY
  local rok = tonumber(ck:match("^...2(..)"))
  if rok then
    rok = 2000 + rok
  else
    -- starší jsou 259YY
    rok = 1900 + tonumber(ck:match("^...(..)") )
  end
  -- or ck:match("^...(..)"))
  local current_year = tonumber(os.date("%Y"))
  -- předpokládáme, že nic neni starší, než 100 let
  local stari =  100 - (current_year - rok)
  if stari < 0 then stari = 0 end
  local koeficient = is_duplicate and 1 or 3
  return (stari / koeficient) * (loans+1)
end

local function score_records(data, pujcovanost)
  for k,rec in ipairs(data) do
    local vypujcky = pujcovanost[rec[1]] or {}
    local pocet_vypujcek = vypujcky[1] or 0
    local score = get_score(rec, rec.duplicate, tonumber(pocet_vypujcek))
    rec.score = score
  end
end

--- vybíráme knížky k vyřazení na základě procenta jednotek, které chceme vyřadit
--- @param data table
--- @param percent number how many records should be removed
local function prune(data, percent)
  local signatury2 = {}
  -- rozřadit záznamy poodle 2. signatury
  for _, record in ipairs(data) do
    local sig2 = record[7]
    local curr = signatury2[sig2] or {}
    table.insert(curr, record)
    signatury2[sig2] = curr
  end
  for sig2, records in pairs(signatury2) do
    -- setřídit podle vyřazovacího skóre
    table.sort(records, function(a,b)
      return a.score < b.score
    end)
    local number = math.floor(#records / 100 * percent)
    for i = 1, number do
      records[i].prune = true
    end
  end
end

local data, header = load_tsv(arg[1]) 
local pujcovanost = hash_by_field(load_tsv(arg[2]), 2)


find_duplicates(data)
score_records(data, pujcovanost)
prune(data, 15)

print(table.concat(header, "\t"), "vyradit", "score")
for _, rec in ipairs(data) do
  print(table.concat(rec, "\t"), (rec.prune or "false"), rec.score)
end


