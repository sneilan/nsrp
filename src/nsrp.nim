const
  pkgTitle*       = "nsrp: Nim Steam Review Parser"
  pkgVersion*     = "2026.09.02.2"
  pkgAuthor*      = "Michael Adams, unquietwiki@gmail.com"
  pkgDescription* = "Download Steam(TM) game reviews into three different formats"

# Libraries
import std/[httpclient, json, net, os, parseopt, streams, strscans, strutils, times, uri]

# Global variables
var
  reviewLimit: int = 0
  dataDirectory: string = "."
let
  timeIsNow = now().utc

# Claude-generated function to isolate a substring
proc nchars(input: string; strVal: var string; start: int; n: int): int =
  ## Matches exactly `n` characters.
  if start + n <= input.len:
    strVal = input[start ..< start + n]
    result = n
  # else result stays 0 -> match fails (also validates the length is exactly n)

# Make sure data directory exists
proc prepareDataDir(dirData: string) =
  if(dirData != "."):
    if(not dirExists(dirData)):
      createDir(dirData)

# Grab JSON fragment from API
proc grabAPIData(steamid: int, cursor: string, numPerPage: int = 100): string =  
  var
    client = newHttpClient()
    rawData: string = ""
  try:
    echo "Using cursor: " & cursor
    let
      requestValues: string = "json=1&filter=updated&purchase_type=all&language=all&filter_offtopic_activity=1&num_per_page=" & $numPerPage & "&cursor=" & encodeUrl(cursor)
      url: string = "https://store.steampowered.com/appreviews/" & $steamid & "?" & requestValues
      response = client.get(url)
    rawData = response.body
  except:
    echo "Could not retrieve JSON data from Steam"
  finally:
    client.close()
    return rawData

# Grab initial data and return as a JSON Object
proc grabData(steamid: int): (JsonNode) =
  var
    newData: string = ""
    rawData: string = ""
    cursor: string = "*"
    skip: string = ""
    oldcursor: string = ""
    arrayOfJSON = newJArray()
    newJSON = newJObject()
    totalFetched: int = 0
  try:
    # Okay... so, we're gonna grab the data, shrinking each request to only ask
    # for as many records as we still need (capped at 100 per page), and chain
    # the cursor until we hit the limit or run out of new pages.
    echo "Retrieving data ..."
    while (true):
      var numPerPage = 100
      if reviewLimit > 0:
        let remaining = reviewLimit - totalFetched
        if remaining <= 0:
          break
        numPerPage = min(100, remaining)
      newData = grabAPIData(steamid, cursor, numPerPage)
      let pageJSON = parseJson(newData)
      arrayOfJSON.add(pageJSON)
      var pageCount = 0
      if pageJSON.contains("reviews"):
        pageCount = pageJSON["reviews"].len
        totalFetched += pageCount
      echo "Page returned " & $pageCount & " reviews (requested " & $numPerPage & ")"
      if (reviewLimit > 0 and totalFetched >= reviewLimit):
        break
      if pageCount < numPerPage:
        break # Steam gave back fewer than we asked for; no more data to page through
      if scanf(newData, "$*\"cursor\":$s\"${nchars(20)}\"", skip, cursor):
        if (cursor == oldcursor):
          break
        echo "More records found: " & cursor
        rawData &= newData
        oldcursor = cursor
      else:
        break # no cursor in the response; stop instead of re-requesting forever
    echo "Data pages loaded: " & $arrayOfJSON.len

    # Verify data is valid before proceeding to build out new, cleaner JSON to use
    if(arrayOfJSON[0].contains("query_summary") and arrayOfJSON[0].contains("reviews")):
      newJSON.add("query_summary", arrayOfJSON[0]["query_summary"])
      newJSON.add("reviews", newJArray())
      var added = 0
      for i in 0 ..< arrayOfJSON.len:
        for j in 0 ..< arrayOfJSON[i]["reviews"].len:
          if (reviewLimit > 0 and added >= reviewLimit):
            break
          newJSON["reviews"].add(arrayOfJSON[i]["reviews"][j])
          inc added
    
  except:
    echo "Could not process JSON data"
  finally:
    return (newJSON)

# Generate Markdown format of JSON data
proc makeMarkdown(jsonData: JsonNode, filename: string): (bool) =
  var streamMD = newFileStream(filename, fmWrite)
  if not isNil(streamMD):    
    # Header & summary
    streamMD.writeLine("# Steam Reviews of INSERT TITLE")
    streamMD.writeLine("## Summary")
    streamMD.writeLine("- **DateTime of Report (UTC):** " & $timeIsNow)
    streamMD.writeLine("- **Total Reviews:** " & $jsonData["query_summary"]["total_reviews"].getInt())
    streamMD.writeLine("- **Positive Reviews:** " & $jsonData["query_summary"]["total_positive"].getInt())
    streamMD.writeLine("- **Negative Reviews:** " & $jsonData["query_summary"]["total_negative"].getInt())
    streamMD.writeLine("- **Overall Sentiment:** " & jsonData["query_summary"]["review_score_desc"].getStr())
    streamMD.writeLine("## Reviews")
    streamMD.flush()
    # Cycle through reviews
    for i in 0 ..< jsonData["reviews"].len:
      let
        activeRow = jsonData["reviews"][i]
        playtimeHrs = activeRow["author"]["playtime_forever"].getInt() / 60
      streamMD.writeLine("### Review by: [" & activeRow["author"]["personaname"].getStr() &
        "](" & activeRow["author"]["profile_url"].getStr() & ")")
      streamMD.writeLine()
      # Stats
      if(activeRow["timestamp_updated"].getInt() != activeRow["timestamp_created"].getInt()):
        streamMD.writeLine("**Updated review (UTC):** _" & $fromUnix(activeRow["timestamp_updated"].getInt()).utc.format("yyyy-MM-dd HH:mm") & "_")
      else:
        streamMD.writeLine("**Reviewed (UTC):** _" & $fromUnix(activeRow["timestamp_created"].getInt()).utc.format("yyyy-MM-dd HH:mm") & "_")
      streamMD.writeLine()
      streamMD.write("**Total user reviews made:** _" & $activeRow["author"]["num_reviews"].getInt() & "_")
      streamMD.write("\t\t **Playtime:** _" & playtimeHrs.formatFloat(ffDecimal, 2) & " hours_")
      # Booleans
      if(activeRow["refunded"].getBool()):
        streamMD.write("     **REFUNDED**")
      if(activeRow["received_for_free"].getBool()):
        streamMD.write("     **RECEIVED FOR FREE**")
      streamMD.writeLine()
      streamMD.writeLine()
      # System specs: note that VRAM is an Int, but others are strings, and CPU string has to be "stripped".
      try:
        if(activeRow.contains("hardware")):
          streamMD.writeLine("**CPU:** _" & activeRow["hardware"]["cpu_name"].getStr().strip() & "_" &
            "; **Video Card:** _" & activeRow["hardware"]["adapter_description"].getStr() & "_" &
            "; **VRAM (MB):** _" & $activeRow["hardware"]["vram_size"].getInt() & "_" &
            "; **System RAM (MB):** _" & activeRow["hardware"]["system_ram"].getStr() & "_" &
            "; **OS:** _" & activeRow["hardware"]["os"].getStr() & "_")
        else:
          streamMD.writeLine("_No system specs provided_")
      except:
        streamMD.writeLine("_No system specs provided_")
      # Write out actual review
      if activeRow["voted_up"].getBool():
        streamMD.writeLine("#### Positive Review ")
      else:
        streamMD.writeLine("#### Negative Review ")
      let reviewText = activeRow["review"].getStr()
      streamMD.writeLine("```")
      streamMD.writeLine(reviewText)
      streamMD.writeLine("```")
      streamMD.writeLine()
      streamMD.writeLine()
      streamMD.flush()
    # Close file
    streamMD.close()
  echo "Parsing JSON into usable Markdown"  
  return true

# Write out help if no valid input is given
proc writeHelp() =
  echo "=============================================================="
  echo pkgTitle, "; ", pkgVersion
  echo pkgAuthor
  echo pkgDescription
  echo ""
  echo "Add a review limit: nsrp -n:REVEWLIMIT (subsequent command)"
  echo "Specify output dir: nsrp -d:DIRECTORY  (subsequent command)"
  echo "JSON:               nsrp -j:STEAMID"
  echo "Markdown:           nsrp -m:STEAMID"
  echo "HTML:               nsrp -h:STEAMID"
  echo "=============================================================="

# === Parse command line ===
for kind, key, val in getopt():
  case kind
  of cmdLongOption, cmdShortOption:
    case key
    of "d":
      try:
        echo "Setting data output directory to " & val
        dataDirectory = val
      except ValueError:
        echo "Incorrect directory specified"
        quit(1)
    of "n":
      try:
        reviewLimit = parseInt(val)
        echo "Limiting to the latest ", reviewLimit, " reviews ..."
      except ValueError:
        echo "Must enter a valid integer for review limit"
        quit(1)
    of "m":
      try:
        var steamid = parseInt(val)
        echo "Outputting Markdown for SteamID ", steamid
        var data = grabData(steamid)        
        prepareDataDir(dataDirectory)
        let filenameMD = os.joinPath(dataDirectory, $steamid & "_review.md")
        if(makeMarkdown(data, filenameMD)):
          echo "Markdown generated: please review " & filenameMD
        else:
          echo "Failed to produce Markdown"
        quit(0)
      except ValueError:
        echo "Must enter a valid integer for SteamID"
        quit(1)
    of "h":
      try:
        var steamid = parseInt(val)
        echo "Outputting HTML for SteamID (TO BE COMPLETED) ", steamid
        quit(0)
      except ValueError:
        echo "Must enter a valid integer for SteamID"
        quit(1)
    of "j":
      try:
        var steamid = parseInt(val)
        echo "Outputting JSON for SteamID ", steamid
        var data = grabData(steamid)
        prepareDataDir(dataDirectory)
        writeFile(joinPath(dataDirectory, $steamid & "_review.json"),pretty(data))
        quit(0)
      except ValueError:
        echo "Must enter a valid integer for SteamID"
        quit(1)
    else:
      writeHelp()
      quit(0)
  of cmdArgument:
    writeHelp()
    quit(0)
  of cmdEnd:
    break
