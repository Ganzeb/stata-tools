*!parseIhelp Version 1.0 Date: 21.08.2018
*!Inserts .ihlp-files into .sthlp-files


program define expandIhlp, rclass
	 // Should work with older versions but not tested
	*Test preprocessing ihelp files and inserting them
	syntax using/ [, REName NOTest nocomp NOEXpand SUFfix(string)]
	
	/* "nocomp" option allows to run the command on versions of Stata which I did not test for
	if "`nocomp'"!=""{
	 local version = _caller()
	if `version' <= 14.2{
	version `version'
	disp as err "Tested only for Stata version 14.2 and higher."
	disp as err "Your Stata version `version' is not officially supported."
	}
	else{
		version 14.2
		}
	}
	*/
	*version 14.2
	tempname fhin fhout
	
	confirm file `"`using'"'
	*Test whether any include directives exist
	if "`notest'"==""{
		includeTest using `"`using'"'
		local inccnt `r(inccnt)'
		if `r(inccnt)'==0{
			disp as err "No include directives found. Nothing to include into `using'."
			exit
		}
	}
	
	*Get file name to create a new parsed file
	 _getfilename `"`using'"'
	local filename `r(filename)'
	if "`suffix'"=="" local suffix _parsed
	gettoken word rest : filename, parse(".")
	local fileout `word'`suffix'.sthlp
	file open `fhin' using `"`using'"', read 
	file open `fhout' using `"`fileout'"', write replace
	file read `fhin' line
	local linenumber 1
	while r(eof)==0{
		 local incfound 0 // Set a trigger to exclude a line with the INCLUDE
		 if regexm(`"`line'"',"^({INCLUDE)"){
		 *local linesave "`line'"
		 local incfound 1
		 local line = subinstr("`line'", "{" ," ",.) // Remove brackets 
		 local line = subinstr("`line'", "}" ," ",.)
		 local arg = word("`line'",3)
			tempname fh2
			capture confirm file `arg'.ihlp
				if _rc{
				 disp as error "File `arg'.ihlp in line `linenumber' not found. Nothing to expand here."
				 continue
				}
			
			file open `fh2' using `arg'.ihlp, read
			file read `fh2' line2
			while r(eof)==0{
				if regexm(`"`line2'"',"^{\* ") continue // Ignore comments in the ihlp-file
				file write `fhout' `"`line2'"' _n
				file read `fh2' line2
			}
			file close `fh2'
			local incfiles "`incfiles' `arg'.ihlp"

		 }
		 if `incfound'!=1 file write `fhout' `"`line'"' _n
		 file read `fhin' line
		 local ++linenumber
	}
	*file write `fh' _n
	file close `fhin'
	file close `fhout'
	disp as txt "File `using' expanded to file `fileout'. "
	disp "`inccnt' .ihlp-files integrated."
	disp "`incfiles' integrated."
	
	if "`rename'"!=""{
		!ren `using' `word'_old.sthlp
		!ren `fileout' `using'
		disp "`using' renamed to `word'_old.sthlp." _n "`fileout' renamed to `using'."
	}
	
	*Saved results
	return local inccnt  `r(inccnt)'
	return local incfiles `incfiles'
end




program define includeTest, rclass
	syntax using/
	tempname fhtest
	local inccnt 0
	file open `fhtest' using `"`using'"', read 
	file read `fhtest' line
	while r(eof)==0{
		if regexm(`"`line'"',"^({INCLUDE)"){
			local ++inccnt
		}
		file read `fhtest' line
	}
	file close `fhtest'
	*disp "Include directives found: `inccnt'"
	return local inccnt `inccnt'
end

