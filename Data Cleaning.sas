/* 0. IMPORT DATA */

PROC IMPORT OUT= WORK.raw_data
			DATAFILE= "/home/u64292383/E-commerce discounts/raw_data.xlsx" 
			DBMS=xlsx
			REPLACE;
			SHEET="Raw Data"; 
			GETNAMES=YES;
RUN;

/* 1. MAKE COPY OF DATA FOR CLEANING AND FIX ISSUES WITH IMPORTING */

DATA data;
	SET raw_data;
RUN;
/* Imported data included extra empty rows, need removal */
options missing = ' ';
DATA data;
	SET data;
	IF missing(CATS(of _all_)) THEN delete;
RUN;
options missing = .;

/* 2. STANDARDIZE DATA

/* Change 'NULL' strings values to '' */
DATA data;
	SET data;
	ARRAY variablesOfInterest _character_;
	DO OVER variablesOfInterest;
		IF variablesOfInterest='NULL' THEN variablesOfInterest='';
	END;
RUN;

/* Check if column data types are correct */
PROC CONTENTS DATA=data;
RUN;
/* Must convert TAX and LOYALTY_ID from character to numeric data types */
DATA data (drop=old1 old2);
	SET data (rename=(TAX=old1 LOYALTY_ID=old2));
	TAX = input(old1, 8.);
	FORMAT TAX BEST.;
	LOYALTY_ID = input(old2, 8.);
	FORMAT LOYALTY_ID BEST.;
RUN;

/* 3. FIND AND REMOVE UNNECESSARY COLUMNS */

/* Find empty columns */
PROC FORMAT;
	VALUE $missfmt ' '='Missing' other='Non-Missing';
	VALUE  missfmt  . ='Missing' other='Non-Missing';
RUN;
PROC FREQ DATA=data; 
	FORMAT _char_ $missfmt.;
	TABLES _char_ / missing missprint nocum nopercent;
	FORMAT _numeric_ missfmt.;
	TABLES _numeric_ / missing missprint nocum nopercent;
RUN;
/* We can see column TRANS_DATE, CUST_ALT_REGION, NOTES, CUST_NOTES, DISCOUNT_C
 are empty, must be removed */
DATA data (drop=TRANS_DATE CUST_ALT_REGION NOTES CUST_NOTES DISCOUNT_C);
	SET data;
RUN;

/* Check if columns REGION, CUST_REGION, CUST_AREA are identical */
PROC SQL;
	SELECT * 
		FROM data
		WHERE REGION <> CUST_REGION
			AND REGION <> CUST_AREA
			AND CUST_REGION <> CUST_AREA;
QUIT;
/* Table is empty so columns are identical, 
must remove CUST_REGION and CUST_AREA columns */
DATA data (drop=CUST_REGION CUST_AREA);
	SET data;
RUN;

/* Look at frequency tables to check if any columns are redundant or not useful */
PROC FREQ DATA=data; 
RUN;
/* NO_OF_ITEMS column is all 0 and SPECIAL_REQUESTS column is all 'N/A' */
/* Remove NO_OF_ITEMS and SPECIAL_REQUESTS columns */
DATA data (drop=NO_OF_ITEMS SPECIAL_REQUESTS);
	SET data;
RUN;

/* 4. FIX BROKEN COLUMNS */ 

/* Look at frequency tables to check if any columns have abnormalities*/
PROC FREQ DATA=data; 
RUN;
/* One record is lowercase 'y' instead of uppercase 'Y' for LOYALTY column */
/* Change lowercase 'y' to uppercase 'Y' for LOYALTY column */
DATA data;
	SET data;
	IF LOYALTY = 'y' then LOYALTY = 'Y';
RUN;

/* The below table shows how item volumes are recorded in ITEM_VOL column 
for months JAN2019 and FEB2019, but after FEB2019 they are recorded 
in the ITEM_VOLUME column. Most likely this issuse is caused by the 
March 2019 data migration */
PROC PRINT DATA=data (keep=TRANS_ID MONTH ITEM_VOL ITEM_VOLUME);
RUN;
/* Fill empty ITEM_VOL values with ITEM_VOLUME values fixes this issue. */
DATA data (drop=ITEM_VOLUME);
	SET data;
	IF ITEM_VOL= . THEN ITEM_VOL=ITEM_VOLUME;
RUN;

/* 5. REMOVE DUPLICATES */ 

PROC SORT DATA=data NODUPKEY DUPOUT=duplicate_rows;
	BY _all_;
RUN;

/* 6. CORRUPTIONS TO DATA */

/* Looking at duplicates1 table below we find that 
multiple distinct transactions have the same TRANS_ID */
PROC SORT DATA=data OUT=unique_trans_id NODUPKEY DUPOUT=duplicate_trans_id;
by TRANS_ID;
RUN;
/* Luckily this problem can be ignored for our analysis */
/* In futrue use a primary key on TRANS_ID column to ensure data integrity */

/* LOYALTY and LOYALTY_ID columns are highly corrupted */

/* The below query shows 33 records have LOYALTY as No but has a 
LOYALTY_ID present */
DATA loyalty_integrity_test (keep=TRANS_ID MONTH LOYALTY LOYALTY_ID ID_PRESENT);
	SET data;
	IF LOYALTY_ID = . THEN ID_PRESENT='No ID';
	ELSE ID_PRESENT='ID';
RUN;
PROC SQL;
	SELECT ID_PRESENT, LOYALTY, COUNT(*) AS NUMBER_OF_RECORDS
	FROM loyalty_integrity_test
	GROUP BY ID_PRESENT, LOYALTY;
QUIT;
/* The below table shows that most of the above discrepancies occur during
JAN2019 and FEB2019 (20). These discepancies are possibly caused by the
March 2019 data migration */
PROC SQL;
	SELECT MONTH, COUNT(*) AS COUNT_OF_INCORRECT_LOYALTY_DATA FROM data
	WHERE LOYALTY = 'N' AND LOYALTY_ID IS NOT NULL
	GROUP BY MONTH;
QUIT;

/* The below table shows all LOYALTY_ID for JAN2019 and FEB2019 records 
are decimals but all other months have integers for LOYALTY_ID. Most likley 
another issue caused by the March 2019 data migration */
DATA no_loyalty_id (keep=MONTH LOYALTY LOYALTY_ID);
	SET data;
	WHERE LOYALTY_ID <> .;
RUN;
/* Unfortunately, not much can be done to fix the above LOYALTY 
and LOYALTY_ID issues */
/* Fortunately, loyalty data is not useful for our analysis so 
data integrity is not necessary. Will leave data as is */

/* Data migration issues can be improved by: 
	- Using Data Stewards – Planning, Implementation, Post-migration
	- Using “Migration simulations” – test migration on subset of data first
	- Validate data before and after migration
	- Using clear user interface for customers
	- Promoting data driven culture – internal training, guidelines 
	and best practices
	- Investigate failures’ root cause (human error, too many data sources etc.
*/

/* 7. RELABLE VALUES FOR CLARITY */

/* Change REGION column values from region codes to full region names, 
and change DISCOUNT_CODE column lable and values */
DATA data;
	INFORMAT REGION $24.;
	FORMAT REGION $24.;
	
	INFORMAT DISCOUNT $21.;
	FORMAT DISCOUNT $21.;
	LENGTH DISCOUNT $ 21;
	
	SET data (rename=(REGION=REGION_CODE DISCOUNT_CODE=DISCOUNT));
	INFORMAT REGION $24.;
	FORMAT REGION $24.;
	IF REGION_CODE='EE' THEN REGION='East of England';
	IF REGION_CODE='EM' THEN REGION='East Midlands';
	IF REGION_CODE='GL' THEN REGION='Greater London';
	IF REGION_CODE='NE' THEN REGION='North East ';
	IF REGION_CODE='NW' THEN REGION='North West';
	IF REGION_CODE='SC' THEN REGION='Scotland';
	IF REGION_CODE='SE' THEN REGION='South East';
	IF REGION_CODE='SW' THEN REGION='South West';
	IF REGION_CODE='WL' THEN REGION='Wales';
	IF REGION_CODE='WM' THEN REGION='West Midlands';
	IF REGION_CODE='YH' THEN REGION='Yorkshire and the Humber';
	
	IF DISCOUNT=' ' THEN DISCOUNT='No Discount';
	IF DISCOUNT='SPRINGCLEAN' THEN DISCOUNT='Spring Clean Discount';
	IF DISCOUNT='SUMMERSALE' THEN DISCOUNT='Summer Sale Discount';
RUN;

/* 8. EXPORT DATA */

PROC EXPORT DATA=data
			OUTFILE= "/home/u64292383/E-commerce discounts/cleaned_data.xlsx" 
			DBMS=xlsx
			REPLACE;
RUN;
