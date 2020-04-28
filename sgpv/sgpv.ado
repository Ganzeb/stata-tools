*! A wrapper program for calculating the Second-Generation P-Values and their associated diagnosis
*!Version 1.01 : Changed name of option 'perm' to 'permanent' to be inline with Standard Stata names of options; removed some inconsistencies between help file and command file (missing abbreviation of pi0-option, format-option was already documented), removed old dead code; enforced and fixed the exclusivity of 'matrix', 'estimate' and prefix-command -> take precedence over replaying ; shortened subcommand menuInstall to menu 
*!Version 1.00 : Initial SSC release, no changes compared to the last Github version.
*!Version 0.99 : Removed automatic calculation of Fcr -> setting the correct interval boundaries of option altspace() not possible automatically
*!Version 0.98a: Displays now the full name of a variable in case of multi equation commands. Shortened the displayed result and added a format option -> get s overriden by the same named option of matlistopt(); Do not calculate any more results for coefficients in r(table) with missing p-value -> previously only checked for missing standard error which is sometimes not enough, e.g. in case of heckman estimation. 
*!Version 0.98 : Added a subcommand to install the dialog boxes to the User's menubar. Fixed an incorrect references to the leukemia example in the help file.
*!Version 0.97 : Further sanity checks of the input to avoid conflict between different options, added possibility to install dialog box into the User menubar.
*!Version 0.96 : Added an example how to calculate all statistics for the leukemia dataset; minor fixes in the documentation of all commands and better handling of the matrix option.
*!Version 0.95 : Fixed minor mistakes in the documentation, added more information about SGPVs and more example use cases; minor bugfixes; changed the way the results are presented
*!Version 0.90 : Initial Github release

/*
To-Do(Things that I wish to implement at some point or that I think that might be interesting to have: 
	- Write a certification script which checks all possible errors (help cscript)
	- Make error messages more descriptive and give hints how to resolve the problems.
	- allow more flexible parsing of coefficient names -> make it easier to select coefficients for the same variable across different equations
	- support for more commands which do not report their results in a matrix named "r(table)". (Which would be the relevant commands?)
	- Make results exportable or change the command to an e-class command to allow processing in commands like esttab or estpost from Ben Jann 
	- Make matrix parsing more flexible and rely on the names of the rows for identifiying the necessary numbers; allow calculations for more than one stored estimate
	- Return more infos (Which infos are needed for further processing?)
	- Allow plotting of the resulting SGPVs against the normal p-values directly after the calculations -> use user-provided command matrixplot instead?
	- change the help file generation from makehlp to markdoc for more control over the layout of the help files -> currently requires a lot of manual tuning to get desired results.
	- improve the speed of fdrisk.ado -> the integration part takes too long. -> switch over to Mata integration functions provided by moremata-package
	- add an immidiate version of sgpvalue similar like ttesti-command; allow two sample t-test equivalent -> currently the required numbers need be calculated or extracted from these commands.
*/

capture program drop sgpv
program define sgpv, rclass
version 12.0
*Parse the initial input 
capture  _on_colon_parse `0'


*Check if anything to calculate is given
if _rc & "`e(cmd)'"=="" & (!ustrregexm(`"`0'"',"matrix\(\w+\)") & !ustrregexm(`"`0'"',"m\(\w+\)") ) & (!ustrregexm(`"`0'"',"estimate\(\w+\)") & !ustrregexm(`"`0'"',"e\(\w+\)") ) & !ustrregexm(`"`0'"',"menu") { // If the command was not prefixed and no previous estimation exists. -> There should be a more elegant solution to this problem 
	disp as error "No last estimate or matrix, saved estimate for calculating SGPV found."
	disp as error "No subcommand found either."
	disp as error "Make sure that the matrix option is correctly specified as 'matrix(matrixname)' or 'm(matrixname)' . "
	disp as error "Make sure that the estimate option is correctly specified as 'estimate(stored estimate name)' or 'e(stored estimate name)' . "
	disp as error "The only currently available subcommand is 'menu'."
	exit 198
}


if !_rc{
	local cmd `"`s(after)'"'
	local 0 `"`s(before)'"' 
} 

**Define here options
syntax [anything(name=subcmd)] [, Quietly  Estimate(name)  Matrix(name) MATListopt(string asis) COEFficient(string) NOBonus(string) nulllo(real 0) nullhi(real 0)  ALTWeights(string) ALTSpace(string asis) NULLSpace(string asis) NULLWeights(string) INTLevel(string) INTType(string) Pi0(real 0.5) FORmat(str) PERMament  debug  /*Display additional messages: undocumented*/ ] 

***Parsing of subcommands -> Might be added as a new feature to use only one command for SGPV calculation
/* Potential subcommands: value, power, fdrisk, plot, menuInstall
if "`subcmd'"!=""{
	if !inlist("`subcmd'","value","power","fdrisk","plot" ) stop "Unknown subcommand `subcmd'. Allowed subcommands are value, power, fdrisk and plot."
	local 0_new `0'
	gettoken 
	ParseSubcmd `subcmd', 
	
}
*/
if "`subcmd'"=="menu"{
	menuInstall , `permament'
	exit
}


***Option parsing
if "`cmd'"!="" & ("`estimate'"!="" | "`matrix'"!=""){
	disp as error "Options 'matrix' and 'estimate' cannot be used in combination with a new estimation command."
	exit 198
} 
else if "`estimate'"!="" & "`matrix'"!=""{
	stop "Setting both options 'estimate' and 'matrix' is not allowed."
} 

	*Saved Estimation
	if "`estimate'"!=""{
		qui estimates dir
		if regexm("`r(names)'","`estimate'"){
		qui estimates restore `estimate'
		}
		else{
			disp as error "No saved estimation result with the name `estimate' found."
			exit 198
		}
	}


	*Arbitrary matrix 
	if "`matrix'"!=""{
		capture confirm matrix `matrix'
		if _rc{
			disp as error "Matrix `matrix' does not exist."
			exit 198
		}
		else{ 
		  //Initial check if rows are correctly named as a crude check that the rows contain the expected numbers
		   local matrown : rownames `matrix'
			if "`:word 1 of `matrown''"!="b" | "`:word 2 of `matrown''"!="se" | "`:word 4 of `matrown''"!="pvalue" | "`:word 5 of `matrown''"!="ll" | "`:word 6 of `matrown''" !="ul"{
			stop "The matrix `matrix' does not have the required format. See the {help sgpv##matrix_opt:help file} for the required format and make sure that the rows of the matrix are labelled correctly."
			}
			local inputmatrix `matrix'
	  }
	}

	**Process fdrisk options
	if `nulllo' ==. stop "No missing value for option 'nulllo' allowed. One-sided intervals are not yet supported."
	if `nullhi' ==. stop "No missing value for option 'nullhi' allowed. One-sided intervals are not yet supported."
	*Nullspace option
	if "`nullspace'"!=""{
		local nullspace `nullspace'
	}
	else if `nullhi'!= `nulllo'{
		local nullspace `nulllo' `nullhi'
	}
	else if `nullhi'== `nulllo'{
		local nullspace `nulllo'
	}
	*Intlevel
	if "`intlevel'"!=""{
		local intlevel = `intlevel'
	}
	else{
		local intlevel 0.05
	}
	
	*Inttype
	if "`inttype'"!="" & inlist("`inttype'", "confidence","likelihood"){
		local inttype `inttype'
	}
	else if "`inttype'"!="" & !inlist("`inttype'", "confidence","likelihood"){
		stop "Parameter intervaltype must be one of the following: confidence or likelihood "
	}
	else{
		local inttype "confidence"
	}

	*Nullweights
	if "`nullweights'"!=""  {
		local nullweights `nullweights'
	}
	else if  "`nullweights'"=="" & "`nullspace'"=="`nulllo'"{
		local nullweights "Point"
	}
	else if "`nullweights'"=="" & `:word count `nullspace''==2{ //Assuming that Uniform is good default nullweights for a nullspace with two values -> TruncNormal will be chosen only if explicitly set.
		local nullweights "Uniform" 
	} 
	
	*Altweights
	if "`altweights'"!="" & inlist("`altweights'", "Uniform", "TruncNormal"){
		local altweights `altweights'
	}
	else{
		local altweights "Uniform"
	}
	
	*Pi0
	if !(`pi0'>0 & `pi0'<1){
		stop "Values for pi0 need to lie within the exclusive 0 - 1 interval. A prior probability outside of this interval is not sensible. The default value assumes that both hypotheses are equally likely."
	}
	
	
**Parse nobonus option
if !inlist("`nobonus'","deltagap","fdrisk","all","none",""){
	stop `"nobonus option incorrectly specified. It takes only values `"none"', `"deltagap"', `"fdrisk"' or `"all"'. "'
}
if "`nobonus'"=="deltagap"{
	local nodeltagap nodeltagap
	}
	
if "`nobonus'"=="fdrisk"{
	local nofdrisk nofdrisk
}

if "`nobonus'"=="all"{
	local nofdrisk nofdrisk
	local nodeltagap nodeltagap
}

*Assuming that any estimation command will report a matrix named "r(table)" and a macro named "e(cmd)"
if "`cmd'"!=""{
 `quietly'	`cmd'
}
else if "`e(cmd)'"!=""{ // Replay previous estimation
 `quietly'	`e(cmd)'
}
 
 
 
* disp "Start calculating SGPV"
 *Create input vectors
  tempname input  input_new sgpv pval comp rest fdrisk coef_mat
 
 *Set the required input matrix
 if "`matrix'"==""{
  capture confirm matrix r(table) //Check if required matrix was returned by estimation command
	 if _rc{
		disp as error "`e(cmd)' did not return required matrix r(table)."
		exit 198
	 }
	local inputmatrix r(table)
 }
 
 ***Input processing
 mat `input' = `inputmatrix'
 return add // save existing returned results 
 
 *Coefficient selection
 if "`coefficient'"!=""{
	local coefnumb : word count `coefficient'
	forvalues i=1/`coefnumb'{
		capture mat `coef_mat' = (nullmat(`coef_mat'), `input'[1...,"`: word `i' of `coefficient''"])
		if _rc{
			stop "Coefficient `:word `i' of `coefficient'' not found or incorrectly written."
		}
	}
	mat `input'=`coef_mat'
 }
 
 local coln =colsof(`input')

* Hard coded values for the rows from which necessary numbers are extracted
*The rows could be addressed by name, but then at least Stata 14 returns a matrix
* which requires additional steps to come to the same results as with hardcoded row numbers. Unless some one complains, I won't change this restriction.
*The macros for esthi and estlo could be become too large, will fix/rewrite the logic if needed 
*Removing not estimated coefficients from the input matrix
 forvalues i=1/`coln'{
	 if !mi(`:disp `input'[2,`i']') & !mi(`:disp `input'[4,`i']') { // Check here if the standard error or the p-value is missing and treat it is as indication for a variable to omit.
		local esthi `esthi' `:disp `input'[6,`i']'
		local estlo `estlo' `:disp `input'[5,`i']'
		mat `pval' =(nullmat(`pval')\\`input'[4,`i'])
		mat `input_new' = (nullmat(`input_new'), `input'[1..6,`i']) //Get new input matrix with only the elements for which results will be calculated

	 }
 }
  local rownames : colfullnames `input_new' //Save the variable names for later display

 
qui sgpvalue, esthi(`esthi') estlo(`estlo') nullhi(`nullhi') nulllo(`nulllo') nowarnings `nodeltagap' 
if "`debug'"=="debug" disp "Finished SGPV calculations. Starting now bonus Fdr calculations."


mat `comp'=r(results)
return add
 mat colnames `pval' = "P-Value"


if "`nofdrisk'"==""{
*False discovery risks 	
		mat `fdrisk' = J(`:word count `rownames'',1,.)
		mat colnames  `fdrisk' = Fdr
	forvalues i=1/`:word count `rownames''{
	if `=`comp'[`i',1]'==0{

	
		qui fdrisk, nullhi(`nullhi') nulllo(`nulllo') stderr(`=`input_new'[2,`i']') inttype(`inttype') intlevel(`intlevel') nullspace(`nullspace') nullweights(`nullweights') altspace(`=`input_new'[5,`i']' `=`input_new'[6,`i']') altweights(`altweights') sgpval(`=`comp'[`i',1]') pi0(`pi0')  // Not sure yet if these are the best default values -> will need to implement possibilities to set these options
		if "`r(fdr)'"!= "" mat `fdrisk'[`i',1] = `r(fdr)'
				
		}
	}
}

*Final matrix composition before displaying results
if "`nofdrisk'"!="nofdrisk"{
	mat `comp'= `pval',`comp' , `fdrisk'
}
else{
	mat `comp'= `pval',`comp'
}
 mat rownames `comp' = `rownames'

*Change the format of the displayed matrix
Format_Display `comp', format(`format')
 matlist r(display_mat) , title("Comparison of ordinary P-Values and Second Generation P-Values") rowtitle(Variables) `matlistopt'

*matlist `comp' , title("Comparison of ordinary P-Values and Second Generation P-Values") rowtitle(Variables) `matlistopt'
return add
*Return results
return matrix comparison =  `comp'

end

*Re-format the input matrix and return a new matrix to circumvent the limitations set by matlist -> using the cspec and rspec options of matlist requires more code to get these options automatically correct -> for now probably not worth the effort.
program define Format_Display, rclass
syntax name(name=matrix) [, format(string)]
	if `"`format'"'==""{
		local format %5.4f
		} 
	else {
			capture local junk : display `format' 1
			if _rc {
					dis as err "invalid %format `format'"
					exit 120
			}
		}
tempname display_mat
local display_mat_coln : colfullnames `matrix'
local display_mat_rown : rowfullnames `matrix'
mat `display_mat'=J(`=rowsof(`matrix')',`=colsof(`matrix')',.)
forvalues i=1/`=rowsof(`matrix')'{
	forvalues j=1/`=colsof(`matrix')'{
		mat `display_mat'[`i',`j']= `: display `format' `matrix'[`i',`j']'
	}

}
mat colnames `display_mat' = `display_mat_coln'
mat rownames `display_mat' = `display_mat_rown'

return matrix display_mat = `display_mat' 
*return local ecmd "`e(cmd)'" 
*return local ecmdline "`e(cmdline)'"
*return local sgpv_options "`'"

end

*Simulate the behaviour of the R-function with the same name 
program define stop
 args text 
 disp as error `"`text'"'
 exit 198
end

*Make the dialog boxes accessible from the User-menu
program define menuInstall
 syntax [, permament *] 
 if "`permament'"=="permament"{
		capture findfile profile.do, path(STATA;.)
		if _rc{
			local replace replace
			disp "profile.do not found."
			disp "profile.do will be created in the current folder."
			local profile profile.do
		}
		else{
			local replace append
			local profile `"`r(fn)'"'
			disp "Append your existing profile.do"
		}
	 
	 tempname fh
	 file open `fh' using `profile' , write text `replace'
	 
	 file write `fh' `"  window menu append item "stUserStatistics" "SGPV (Main Command) (&sgpv)" "db sgpv" "' _n
	 file write `fh' `"  window menu append item "stUserStatistics" "SGPV Value Calculations (&sgpvalue)" "db sgpvalue" "' _n
	 file write `fh' `"  window menu append item "stUserStatistics" "SGPV Power Calculations (&sgpower)" "db sgpower" "' _n
	 file write `fh' `"  window menu append item "stUserStatistics" "SGPV False Confirmation/Discovery Risk (&fdrisk)" "db fdrisk" "' _n
	 file write `fh' `"  window menu append item "stUserStatistics" "SGPV Plot Interval Estimates (&plotsgpv)" "db plotsgpv" "' _n
	 file write `fh' `" window menu refresh "' _n
	 file close `fh'

 
 }
	window menu clear // Assuming that no one else installs dialog boxes into the menubar. If this assumption is wrong then the code will be changed.
	window menu append submenu "stUserStatistics"  "SGPV"
	window menu append item "SGPV" "SGPV (Main command) (&sgpv)" "db sgpv" 
	window menu append item "SGPV" "SGPV Value Calculations (sgp&value)" "db sgpvalue"
	window menu append item "SGPV" "SGPV Power Calculations (sg&power)" "db sgpower" 
	window menu append item "SGPV" "False Confirmation/Discovery Risk (&fdrisk)" "db fdrisk" 
	window menu append item "SGPV" "SGPV Plot Interval Estimates (p&lotsgpv)" "db plotsgpv"

	window menu refresh
	
end
