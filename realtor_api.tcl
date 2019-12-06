

#		realtor.ca API
#	Tommy Freethy - September 2019
#
# As of writing this, realtor.ca does not have documentation on their API. Someone made a node.js package 
# that wraps the API, they have some information at: https://github.com/Froren/realtorca
#
# Currently I only use this script to get a list of all detached houses in Aurora, Ontario. 
#
# I would like to use the API to monitor listings in the GTA to try to get a feeling of the overall
# state of the housing market in the area.

package require http
package require tls
package require json

namespace eval realtor_api {
	variable _api_address "https://api2.realtor.ca/Listing.svc/PropertySearch_Post"
	
	proc main {} {
		http::register https 443 [list ::tls::socket -tls1 1]
		test_api
	}
	
	proc test_api {} {
		# Can only request for one page of listings at a time
		set CurrentPage 1
		while {1} {
			set Query [::http::formatQuery \
				CultureId 1 \
				ApplicationId 1 \
				PropertySearchTypeId 1 \
				LongitudeMin -79.499225 \
				LongitudeMax -79.412987 \
				LatitudeMin 43.957584 \
				LatitudeMax 44.016609 \
				PriceMin 0 \
				PriceMax 100000000 \
				BuildingTypeId 1 \
				ConstructionStyleId 3 \
				CurrentPage $CurrentPage \
			]
			set Result [realtor_request $Query]
			if {$Result eq ""} {
				break
			}
			set ResultDict [json::json2dict $Result]
			
			set CurrentPage [::dict get $ResultDict "Paging" "CurrentPage"]
			set TotalPages [::dict get $ResultDict "Paging" "TotalPages"]
			
			puts "---------------------------------------"
			puts "Result retrieved for page: $CurrentPage"
			puts "---------------------------------------"
			
			set Listings [::dict get $ResultDict "Results"]
			foreach Listing $Listings {
				set Bathrooms [::dict get $Listing "Building" "BathroomTotal"]
				set Bedrooms [::dict get $Listing "Building" "Bedrooms"]
				if {[llength [split $Bedrooms "+"]] > 1} {
					set ExtraBR [string trim [lindex [split $Bedrooms "+"] 1]]
				}
				
				# Trying to determine lot size (acres) by parsing the various notes, mainly separated by ";" 
				set Size ""
				if {[::dict exists $Listing "Land" "SizeTotal"]} {
					set LandSize [::dict get $Listing "Land" "SizeTotal"]
					foreach Note [split $LandSize ";"] {
						if {[llength [split $Note "|"]] > 1} {
							set Note [string trim [lindex [split $Note "|"] 0]]
						}
						if {[string first "x" $Note] >= 0} {
							set Divider ""
							switch -glob -- $Note {
								"*FT*" {set Divider 43560}
								"*M*" {set Divider 4046}
								"*Acre*" {set Divider 1}
							}
							set Mapped [string trim [string map {"x" "" "M" "" "FT" "" "Acre" ""} $Note]]
							if {[llength $Mapped] == 2 && $Divider ne ""} {
								set Size [format %.2f [expr {double([lindex $Mapped 0]) * [lindex $Mapped 1] / $Divider}]]
								break
							}
						} else {
							if {[string first "Ac" $Note] >= 0} {
								set Size [string trim [string map {"Acres" "" "Acre" "" "Ac" ""} $Note]]
								break
							}
						}
					}
				}
				set Price [::dict get $Listing "Property" "Price"]
				puts "Bedrooms=$Bedrooms, Bathrooms=$Bathrooms, Price=$Price, Size=$Size"
			}
			if {$CurrentPage == $TotalPages} {
				break
			}
			incr CurrentPage
		}
	}
	
	#Nice and simple request. No cookies, API keys, or authorization. Not even SNI.
	proc realtor_request {Query} {
		variable _api_address
		
		# puts "realtor_request...sending request to: $URL"
		if {[catch {
			set Token [::http::geturl $_api_address \
				-timeout 10000 \
				-query $Query \
			]
		} error]} {
			puts "realtor_request...Something went wrong: $error"
			return "";
		}
		
		if {[http::status $Token] eq "timeout"} {
			puts "realtor_request...timeout"
			http::cleanup $Token
		}
		if {[http::ncode $Token] ne 200} {
			# For debugging. Outputs contents of HTTP header
			foreach {Name Value} [http::meta $Token] {
				puts "realtor_request...Code not 200, $Name=$Value"
			}
			return ""
		}
		
		set Result [http::data $Token]
		http::cleanup $Token
		return $Result
	}
}


realtor_api::main

