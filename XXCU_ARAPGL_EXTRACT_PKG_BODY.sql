create or replace
PACKAGE BODY XXCU_ARAPGL_EXTRACT_PKG AS
  --*****************************************************************************
  --Module      : GL
  --Type        : PL/SQL - Package
  --Filename    : $XXCU_TOP/admin/sql/XXCU_ARAPGL_EXTRACT_PKG.pkb
  --Author      : TCS
  --Version     : 1.0
  --
  -- Description: Extract AR AP and GL data for Bank Reconciliation. file will be placed in
  -- log procedures
  -- *****************************************************************************
  -- DATE         NAME               History
  -- 26-11-2023   TCS                Initial Version
  -- -------------------------------------------------
PROCEDURE GENERATE_AR_EXTRACT(
    PV_IN_ORG_ID       IN NUMBER,
    PV_IN_CURRENCY     IN VARCHAR2,
	  PV_IN_GL_ACCOUNT   IN VARCHAR2,
    PV_IN_GL_DATE_FROM IN VARCHAR2,
    PV_IN_GL_DATE_TO   IN VARCHAR2
    )
	IS
  LV_FILE_HANDLER UTL_FILE.FILE_TYPE;
  LV_DIR SYS.ALL_DIRECTORIES.DIRECTORY_PATH%TYPE := 'EPM_DIR_GEN_OUT';
  --LV_FILE_NAME VARCHAR2(240)                 := 'test'||'.csv';
  LV_FILE_NAME VARCHAR2(240)                 := 'PB_AR_Extract_Bank_Recon_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24MISS')||'.csv';
  --LV_FILE_NAME_AP VARCHAR2(240)                 := 'PB AP Extract For Bank Reconciliation_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24:MI:SS')||'.csv';
  --LV_FILE_NAME_GL VARCHAR2(240)                 := 'PB GL Extract For Bank Reconciliation_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24:MI:SS')||'.csv';
  LV_FROM_GL_DATE VARCHAR2(50) ;
  LV_TO_GL_DATE VARCHAR2(50) ;
  LV_IN_ORG_ID       NUMBER;
  LV_IN_CURRENCY     VARCHAR2(50);
  LV_IN_GL_ACCOUNT   VARCHAR2(50);
  LV_OUTPUT_HEADER VARCHAR2 (4000);
  l_ar_count NUMBER :=0;
  L_DATE DATE ;
  CURSOR CUR_AR_EXTRACT
  IS
  SELECT  nvl(xal.accounted_dr,-xal.accounted_cr) amount,
          acr.receipt_date rec_date,
          acr.attribute1 payment_ref,
          acr.attribute6 payer_acct_number,
          acr.attribute7 payer_name,
          acr.currency_code currency_code,
          acr.comments comments,
          hca.account_number customer_number,
          hp.party_name customer_name,
          acr.receipt_number receipt_number,
          haou.short_code company_code,
          haou.name company,
          cba.bank_account_num pay_to_acct_num,
          cb.bank_name remit_bank,
          arm.name payment_method,
          acr.attribute8 file_name,
          gcc.segment2 gl_account,
          gcc.segment8 object
  FROM gl.gl_je_headers gjh,
       gl.gl_je_lines gjl,
       gl.gl_code_combinations gcc,
       gl.gl_periods glp,
       gl.gl_import_references imp,
       xla.xla_transaction_entities xte,
       xla.xla_ae_lines xal,
       xla.xla_ae_headers xah,
       xla.xla_events xe,
       ar.ar_cash_receipts_all acr,
       ar_cash_receipt_history_all acrh,
       apps.hr_operating_units haou,
       hz_cust_accounts hca,
       hz_parties hp,
       ce_bank_acct_uses_all cbaua,
       ce_bank_accounts cba,
       ce_banks_v cb,
       ar_receipt_methods arm

 WHERE     1 = 1
       AND gjh.je_header_id = gjl.je_header_id
       --AND gjl.code_combination_id = gcc.code_combination_id
       AND gjh.period_name = glp.period_name
       AND gjl.je_header_id = imp.je_header_id
       AND gjl.je_line_num = imp.je_line_num
       AND imp.gl_sl_link_id = xal.gl_sl_link_id
       AND imp.gl_sl_link_table = xal.gl_sl_link_table
       AND xal.application_id = xah.application_id
       AND xal.ae_header_id = xah.ae_header_id
       AND xah.application_id = xe.application_id
       AND xah.event_id = xe.event_id
       AND xe.application_id = xte.application_id
       AND xe.entity_id = xte.entity_id
       AND gjh.je_source = 'Receivables'
       AND xte.entity_code = 'RECEIPTS'
       AND xal.accounting_class_code='CASH'
       AND xte.source_id_int_1 = acr.cash_receipt_id
       AND imp.reference_5=xte.entity_id
       AND acr.cash_receipt_id=acrh.cash_receipt_id
       AND acr.org_id=acrh.org_id
       AND acrh.CURRENT_RECORD_FLAG='Y'
       AND acrh.postable_flag='Y'
       AND acr.pay_from_customer=hca.cust_account_id
       AND acr.org_id=haou.organization_id
       AND acrh.org_id=haou.organization_id
       AND hca.party_id=hp.party_id
       AND acr.remit_bank_acct_use_id=cbaua.bank_acct_use_id
       AND cbaua.bank_account_id=cba.bank_account_id
       AND cba.bank_id=cb.bank_party_id
	     --AND gcc.code_combination_id=cba.cash_clearing_ccid
       AND gcc.code_combination_id=xal.code_combination_id
       AND acr.receipt_method_id=arm.receipt_method_id
	     AND arm.name in('Imported Receipts','Manual Receipts','Misc Receipts')
       AND haou.organization_id=NVL(LV_IN_ORG_ID,haou.organization_id)--1712
       AND acr.currency_code=NVL(LV_IN_CURRENCY,acr.currency_code)--NOK
       AND gcc.segment2=NVL(LV_IN_GL_ACCOUNT,gcc.segment2)--150000
       AND  acrh.gl_date BETWEEN fnd_date.canonical_to_date(LV_FROM_GL_DATE) AND fnd_date.canonical_to_date(LV_TO_GL_DATE)
       --AND acrh.gl_date BETWEEN TO_DATE(LV_FROM_GL_DATE,'DD-MON-YY') AND TO_DATE(LV_TO_GL_DATE,'DD-MON-YY')
       --AND acrh.gl_date between NVL(to_date(PV_IN_GL_DATE_FROM,'YYYY/MM/DD HH24:MI:SS'),acrh.gl_date) and NVL(to_date(PV_IN_GL_DATE_TO,'YYYY/MM/DD HH24:MI:SS'),acrh.gl_date)
	     /*AND acrh.gl_date BETWEEN COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_FROM),acrh.gl_date)
                                   AND COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_TO), acrh.gl_date)*/
     --AND to_date(acrh.gl_date,'DD-MON-YYYY') BETWEEN TO_DATE(LV_FROM_GL_DATE,'DD-MON-YYYY') AND TO_DATE(LV_TO_GL_DATE,'DD-MON-YYYY')
     --AND acrh.gl_date between '01-OCT-2023' AND '30-OCT-2023'
       --AND gjh.period_name='OCT-23'--:p_period_name
      -- and acr.receipt_number='01022023_10166338_5393'
       --and acr.cash_receipt_id=16473029
       --AND acrh.cash_receipt_id=20654939
    ;

BEGIN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Starting XXCU_ARAPGL_EXTRACT_PKG.GENERATE_AR_EXTRACT procedure');
  FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_DIR:'||LV_DIR);
  FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_FILE_NAME:'||LV_FILE_NAME);
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Befor handler');
  --LV_FILE_HANDLER := UTL_FILE.FOPEN(LV_DIR,LV_FILE_NAME, 'W','32767');
  FND_FILE.PUT_LINE(FND_FILE.LOG,'After handler');
  --FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_FILE_HANDLER:'||LV_FILE_HANDLER);
  --FND_MESSAGE.SET_NAME ('XXCU', 'XXCU_AR_EXTRACT_HEADER');
  --FND_FILE.PUT_LINE(FND_FILE.LOG,'After FND message');
  --LV_OUTPUT_HEADER := FND_MESSAGE.GET;
  --UTL_FILE.PUT(LV_FILE_HANDLER,LV_OUTPUT_HEADER);
  --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,LV_OUTPUT_HEADER);
  LV_TO_GL_DATE   :=  PV_IN_GL_DATE_TO ;
  LV_FROM_GL_DATE :=  PV_IN_GL_DATE_FROM ;
  LV_IN_ORG_ID       :=PV_IN_ORG_ID;
  LV_IN_CURRENCY     :=PV_IN_CURRENCY;
  LV_IN_GL_ACCOUNT   :=PV_IN_GL_ACCOUNT;
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Date From :'||LV_FROM_GL_DATE);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Date To :'  ||LV_TO_GL_DATE);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Org ID :'||LV_IN_ORG_ID);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Currency Code :'  ||LV_IN_CURRENCY);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'GL Account :'||LV_IN_GL_ACCOUNT);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'File Name :'||LV_FILE_NAME);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'PV_IN_GL_DATE_TO :'||PV_IN_GL_DATE_TO);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'PV_IN_GL_DATE_FROM :'||PV_IN_GL_DATE_FROM);
  --FND_FILE.PUT_LINE (FND_FILE.LOG,'PV_IN_GL_DATE_TO :'||to_date(PV_IN_GL_DATE_TO,'DD-MON-YYYY'));
  --FND_FILE.PUT_LINE (FND_FILE.LOG,'PV_IN_GL_DATE_FROM :'||to_date(PV_IN_GL_DATE_FROM,'DD-MON-YYYY'));

BEGIN
SELECT  COUNT(1)
INTO l_ar_count
  FROM gl.gl_je_headers gjh,
       gl.gl_je_lines gjl,
       gl.gl_code_combinations gcc,
       gl.gl_periods glp,
       gl.gl_import_references imp,
       xla.xla_transaction_entities xte,
       xla.xla_ae_lines xal,
       xla.xla_ae_headers xah,
       xla.xla_events xe,
       ar.ar_cash_receipts_all acr,
       ar_cash_receipt_history_all acrh,
       hr.hr_all_organization_units haou,
       hz_cust_accounts hca,
       hz_parties hp,
       ce_bank_acct_uses_all cbaua,
       ce_bank_accounts cba,
       ce_banks_v cb,
       ar_receipt_methods arm

 WHERE     1 = 1
       AND gjh.je_header_id = gjl.je_header_id
       --AND gjl.code_combination_id = gcc.code_combination_id
       AND gjh.period_name = glp.period_name
       AND gjl.je_header_id = imp.je_header_id
       AND gjl.je_line_num = imp.je_line_num
       AND imp.gl_sl_link_id = xal.gl_sl_link_id
       AND imp.gl_sl_link_table = xal.gl_sl_link_table
       AND xal.application_id = xah.application_id
       AND xal.ae_header_id = xah.ae_header_id
       AND xah.application_id = xe.application_id
       AND xah.event_id = xe.event_id
       AND xe.application_id = xte.application_id
       AND xe.entity_id = xte.entity_id
       AND gjh.je_source = 'Receivables'
       AND xte.entity_code = 'RECEIPTS'
       AND xal.accounting_class_code='CASH'
       AND xte.source_id_int_1 = acr.cash_receipt_id
       AND imp.reference_5=xte.entity_id
       AND acr.cash_receipt_id=acrh.cash_receipt_id
       AND acr.org_id=acrh.org_id
       AND acrh.CURRENT_RECORD_FLAG='Y'
       AND acrh.postable_flag='Y'
       AND acr.pay_from_customer=hca.cust_account_id
       AND acr.org_id=haou.organization_id
       AND acrh.org_id=haou.organization_id
       AND hca.party_id=hp.party_id
       AND acr.remit_bank_acct_use_id=cbaua.bank_acct_use_id
       AND cbaua.bank_account_id=cba.bank_account_id
       AND cba.bank_id=cb.bank_party_id
	     --AND gcc.code_combination_id=cba.cash_clearing_ccid
       AND gcc.code_combination_id=xal.code_combination_id
       AND acr.receipt_method_id=arm.receipt_method_id
	     AND arm.name in('Imported Receipts','Manual Receipts','Misc Receipts')
       AND haou.organization_id=NVL(LV_IN_ORG_ID,haou.organization_id)--1712
       AND acr.currency_code=NVL(LV_IN_CURRENCY,acr.currency_code)--NOK
       AND gcc.segment2=NVL(LV_IN_GL_ACCOUNT,gcc.segment2)--150000
       AND acrh.gl_date BETWEEN fnd_date.canonical_to_date(LV_FROM_GL_DATE) AND fnd_date.canonical_to_date(LV_TO_GL_DATE)
       --AND acrh.gl_date between NVL(to_date(PV_IN_GL_DATE_FROM,'YYYY/MM/DD HH24:MI:SS'),acrh.gl_date) and NVL(to_date(PV_IN_GL_DATE_TO,'YYYY/MM/DD HH24:MI:SS'),acrh.gl_date)
	     /*AND acrh.gl_date BETWEEN COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_FROM),acrh.gl_date)
                                   AND COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_TO), acrh.gl_date)*/
     --AND to_date(acrh.gl_date,'DD-MON-YYYY') BETWEEN TO_DATE(LV_FROM_GL_DATE,'DD-MON-YYYY') AND TO_DATE(LV_TO_GL_DATE,'DD-MON-YYYY')
     --AND acrh.gl_date between '01-OCT-2023' AND '30-OCT-2023'
       --AND gjh.period_name='OCT-23'--:p_period_name
      -- and acr.receipt_number='01022023_10166338_5393'
       --and acr.cash_receipt_id=16473029
       --AND acrh.cash_receipt_id=20654939
    ;
	
FND_FILE.PUT_LINE(FND_FILE.LOG,'Total AR count : '||l_ar_count);
EXCEPTION
WHEN OTHERS THEN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Error during AR count : '||SQLERRM);
END;

IF l_ar_count>0 THEN

  BEGIN
  LV_FILE_HANDLER := UTL_FILE.FOPEN(LV_DIR,LV_FILE_NAME, 'W','32767');
  UTL_FILE.PUT(LV_FILE_HANDLER,'amount'||'^'||'rec_date'||'^'||'payment_ref'||'^'||'payer_acct_number'||'^'||'payer_name'||'^'||'currency_code'||'^'||'comments'||'^'||'customer_number'||'^'||'customer_name'||'^'||'receipt_number'||'^'||'company_code'||'^'||'company'||'^'||'pay_to_acct_num'||'^'||'remit_bank'||'^'||'payment_method'||'^'||'file_name'||'^'||'gl_account'||'^'||'object'||chr(10));

    FOR REC_AR_EXTRACT IN CUR_AR_EXTRACT
    LOOP
    --FND_FILE.PUT_LINE(FND_FILE.LOG,'Inside loop');
      --UTL_FILE.PUT(LV_FILE_HANDLER,CHR(13)||CHR(10));
      UTL_FILE.PUT_LINE(LV_FILE_HANDLER,REC_AR_EXTRACT.AMOUNT||'^'||REC_AR_EXTRACT.rec_date||'^'||REC_AR_EXTRACT.payment_ref||'^'||REC_AR_EXTRACT.payer_acct_number ||'^'||REC_AR_EXTRACT.payer_name||'^'||REC_AR_EXTRACT.currency_code||'^'||REC_AR_EXTRACT.comments||'^'||REC_AR_EXTRACT.customer_number||'^'||REC_AR_EXTRACT.customer_name||'^'||REC_AR_EXTRACT.receipt_number||'^'||REC_AR_EXTRACT.company_code||'^'||REC_AR_EXTRACT.company||'^'||REC_AR_EXTRACT.pay_to_acct_num||'^'||REC_AR_EXTRACT.remit_bank||'^'||REC_AR_EXTRACT.payment_method||'^'||REC_AR_EXTRACT.file_name||'^'||REC_AR_EXTRACT.gl_account||'^'||REC_AR_EXTRACT.object);
      --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,REC_AR_EXTRACT.AMOUNT ||';'||REC_AR_EXTRACT.payment_ref||';'||REC_AR_EXTRACT.payer_acct_number ||';'||REC_AR_EXTRACT.payer_name||';'||REC_AR_EXTRACT.currency_code||';'||REC_AR_EXTRACT.comments||';'||REC_AR_EXTRACT.customer_number||';'||REC_AR_EXTRACT.customer_name||';'||REC_AR_EXTRACT.receipt_number||';'||REC_AR_EXTRACT.company_code||';'||REC_AR_EXTRACT.company||';'||REC_AR_EXTRACT.pay_to_acct_num||';'||REC_AR_EXTRACT.remit_bank||';'||REC_AR_EXTRACT.payment_method||';'||REC_AR_EXTRACT.file_name||';'||REC_AR_EXTRACT.gl_account||';'||REC_AR_EXTRACT.object);
    END LOOP;

  EXCEPTION
  WHEN NO_DATA_FOUND THEN
    FND_FILE.PUT_LINE(FND_FILE.LOG,'No Records Retrieved');
  END;
  utl_file.fflush(LV_FILE_HANDLER);
  UTL_FILE.FCLOSE(LV_FILE_HANDLER);

ELSE 
FND_FILE.PUT_LINE(FND_FILE.LOG,'ZERO byte AR file generated');
END IF;

EXCEPTION
WHEN OTHERS THEN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Error in GENERATE_AR_EXTRACT : '||SQLERRM);
END GENERATE_AR_EXTRACT;
PROCEDURE GENERATE_AP_EXTRACT(
   	PV_IN_ORG_ID       IN NUMBER,
    PV_IN_CURRENCY     IN VARCHAR2,
	  PV_IN_GL_ACCOUNT   IN VARCHAR2,
    PV_IN_GL_DATE_FROM IN VARCHAR2,
    PV_IN_GL_DATE_TO   IN VARCHAR2
    )
	IS
  LV_FILE_HANDLER UTL_FILE.FILE_TYPE;
  LV_DIR ALL_DIRECTORIES.DIRECTORY_PATH%TYPE := 'EPM_DIR_GEN_OUT';
  --LV_FILE_NAME VARCHAR2(240)                 := 'PB AR Extract For Bank Reconciliation_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24:MI:SS')||'.csv';
  LV_FILE_NAME VARCHAR2(240)                 := 'PB_AP_Extract_Bank_Recon_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24MISS')||'.csv';
  --LV_FILE_NAME_GL VARCHAR2(240)                 := 'PB GL Extract For Bank Reconciliation_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24:MI:SS')||'.csv';
  LV_FROM_GL_DATE VARCHAR2(50) ;
  LV_TO_GL_DATE VARCHAR2(50) ;
  LV_IN_ORG_ID       NUMBER;
  LV_IN_CURRENCY     VARCHAR2(50);
  LV_IN_GL_ACCOUNT   VARCHAR2(50);
  LV_OUTPUT_HEADER VARCHAR2 (4000);
  LV_AP_COUNT NUMBER :=0;
  CURSOR CUR_AP_EXTRACT
  IS
  SELECT  nvl(xal.accounted_dr,-xal.accounted_cr) amount,
       ipa.payment_date payment_date,
       ipa.unique_remittance_identifier payment_ref,
       ipa.payment_currency_code currency_code,
       ipa.remittance_message1 || ' '||ipa.remittance_message2||' '||ipa.remittance_message3 remittance_msg,
       asa.segment1 supplier_num,
       asa.vendor_name supplier_name,
       aca.check_number payment_number,
       haou.short_code company_code,
       haou.name company,
       ipa.int_bank_account_number pay_from_acct_num,
       ipa.payment_method_code payment_method,
       ipa.int_bank_name remittance_bank,
       gcc.segment2 gl_acct,
       gcc.segment8 object
       /*gir.reference_5,
       xte.entity_id,
       xte.source_id_int_1,
       aca.check_id,
       gir.gl_sl_link_id,
       xah.ae_header_id*/
FROM gl.gl_je_headers gjh,
     gl.gl_je_lines gjl,
     gl.gl_code_combinations gcc,
     gl.gl_periods gp,
     gl.gl_import_references gir,
     --xla.xla_transaction_entities xte,
     XLA_TRANSACTION_ENTITIES_UPG xte,
     xla.xla_ae_lines xal,
     xla.xla_ae_headers xah,
     ap.ap_checks_all aca,
     iby.iby_payments_all ipa,
     apps.hr_operating_units haou,
     AP.ap_suppliers asa

WHERE 1                     = 1
AND gjl.je_header_id        = gjh.je_header_id
AND gcc.code_combination_id = gjl.code_combination_id
AND gjh.period_name         = gp.period_name
AND gir.gl_sl_link_id       =xal.gl_sl_link_id
AND gir.gl_sl_link_table = xal.gl_sl_link_table
AND xal.ae_header_id        =xah.ae_header_id
AND xal.application_id = xah.application_id
AND gjl.je_line_num =gir.je_line_num
AND gjh.je_header_id =gir.je_header_id
AND xah.entity_id=xte.entity_id
AND xal.accounting_class_code='CASH'
AND xte.entity_code='AP_PAYMENTS'
AND xte.application_id = 200
--AND gir.gl_sl_link_id in(140232089,140232088)
AND gjh.je_source='Payables'
AND xte.source_id_int_1 = aca.check_id
AND aca.payment_id=ipa.payment_id
AND aca.org_id=ipa.org_id
AND aca.org_id=haou.organization_id
AND aca.vendor_id=asa.vendor_id
--AND aca.check_number='3455961'
--AND aca.check_id=3155973
AND haou.organization_id=NVL(LV_IN_ORG_ID,haou.organization_id)--1712
AND ipa.payment_currency_code=NVL(LV_IN_CURRENCY,ipa.payment_currency_code)--NOK
AND gcc.segment2=NVL(LV_IN_GL_ACCOUNT,gcc.segment2)--240000
AND ipa.payment_date BETWEEN fnd_date.canonical_to_date(LV_FROM_GL_DATE) AND fnd_date.canonical_to_date(LV_TO_GL_DATE)
/*AND ipa.payment_date BETWEEN COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_FROM),ipa.payment_date)
                                   AND COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_TO), ipa.payment_date)*/
--AND to_date(ipa.payment_date,'DD-MON-YYYY') BETWEEN TO_DATE(LV_FROM_GL_DATE,'DD-MON-YYYY') AND TO_DATE(LV_TO_GL_DATE,'DD-MON-YYYY')
--AND ipa.payment_date between '01-AUG-2023' AND '30-AUG-2023'
    ;

BEGIN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Starting XXCU_ARAPGL_EXTRACT_PKG.GENERATE_AP_EXTRACT procedure');
  FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_DIR:'||LV_DIR);
  FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_FILE_NAME:'||LV_FILE_NAME);
  --LV_FILE_HANDLER := UTL_FILE.FOPEN(LV_DIR,LV_FILE_NAME, 'W');
  --FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_FILE_HANDLER:'||LV_FILE_HANDLER);
  --FND_MESSAGE.SET_NAME ('XXCU', 'XXCU_AP_EXTRACT_HEADER');
  --LV_OUTPUT_HEADER := FND_MESSAGE.GET;
  --UTL_FILE.PUT(LV_FILE_HANDLER,LV_OUTPUT_HEADER);
  --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,LV_OUTPUT_HEADER);
  LV_TO_GL_DATE   :=  PV_IN_GL_DATE_TO;
  LV_FROM_GL_DATE :=  PV_IN_GL_DATE_FROM;
  LV_IN_ORG_ID       :=PV_IN_ORG_ID;
  LV_IN_CURRENCY     :=PV_IN_CURRENCY;
  LV_IN_GL_ACCOUNT   :=PV_IN_GL_ACCOUNT;
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Date From :'||LV_FROM_GL_DATE);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Date To :'  ||LV_TO_GL_DATE);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Org ID :'||LV_IN_ORG_ID);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Currency Code :'  ||LV_IN_CURRENCY);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'GL Account :'||LV_IN_GL_ACCOUNT);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'File Name :'||LV_FILE_NAME);

--BEGIN

BEGIN
SELECT  COUNT(1)
INTO LV_AP_COUNT
FROM gl.gl_je_headers gjh,
     gl.gl_je_lines gjl,
     gl.gl_code_combinations gcc,
     gl.gl_periods gp,
     gl.gl_import_references gir,
     xla.xla_transaction_entities xte,
     xla.xla_ae_lines xal,
     xla.xla_ae_headers xah,
     ap.ap_checks_all aca,
     iby.iby_payments_all ipa,
     hr.hr_all_organization_units haou,
     AP.ap_suppliers asa

WHERE 1                     = 1
AND gjl.je_header_id        = gjh.je_header_id
AND gcc.code_combination_id = gjl.code_combination_id
AND gjh.period_name         = gp.period_name
AND gir.gl_sl_link_id       =xal.gl_sl_link_id
AND gir.gl_sl_link_table = xal.gl_sl_link_table
AND xal.ae_header_id        =xah.ae_header_id
AND xal.application_id = xah.application_id
AND gjl.je_line_num =gir.je_line_num
AND gjh.je_header_id =gir.je_header_id
AND gir.reference_5=xte.entity_id
AND xal.accounting_class_code='CASH'
AND xte.entity_code='AP_PAYMENTS'
--AND gir.gl_sl_link_id in(140232089,140232088)
AND gjh.je_source='Payables'
AND xte.source_id_int_1 = aca.check_id
AND aca.payment_id=ipa.payment_id
AND aca.org_id=ipa.org_id
AND aca.org_id=haou.organization_id
AND aca.vendor_id=asa.vendor_id
--AND aca.check_number='3455961'
--AND aca.check_id=3155973
AND haou.organization_id=NVL(LV_IN_ORG_ID,haou.organization_id)--1712
AND ipa.payment_currency_code=NVL(LV_IN_CURRENCY,ipa.payment_currency_code)--NOK
AND gcc.segment2=NVL(LV_IN_GL_ACCOUNT,gcc.segment2)--240000
AND ipa.payment_date BETWEEN fnd_date.canonical_to_date(LV_FROM_GL_DATE) AND fnd_date.canonical_to_date(LV_TO_GL_DATE)
/*AND ipa.payment_date BETWEEN COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_FROM),ipa.payment_date)
                                   AND COALESCE(fnd_date.canonical_to_date(PV_IN_GL_DATE_TO), ipa.payment_date)*/
--AND to_date(ipa.payment_date,'DD-MON-YYYY') BETWEEN TO_DATE(LV_FROM_GL_DATE,'DD-MON-YYYY') AND TO_DATE(LV_TO_GL_DATE,'DD-MON-YYYY')
--AND ipa.payment_date between '01-AUG-2023' AND '30-AUG-2023'
    ;

FND_FILE.PUT_LINE(FND_FILE.LOG,'Total AP count : '||LV_AP_COUNT);

EXCEPTION
WHEN OTHERS THEN
FND_FILE.PUT_LINE(FND_FILE.LOG,'Error during AP count : '||SQLERRM);
END;

IF LV_AP_COUNT>0 THEN
  LV_FILE_HANDLER := UTL_FILE.FOPEN(LV_DIR,LV_FILE_NAME, 'W');
  UTL_FILE.PUT(LV_FILE_HANDLER,'amount'||'^'||'payment_date'||'^'||'payment_ref'||'^'||'currency_code'||'^'||'remittance_msg'||'^'||'supplier_num'||'^'||'supplier_name'||'^'||'payment_number'||'^'||'company_code'||'^'||'company'||'^'||'pay_from_acct_num'||'^'||'remittance_bank'||'^'||'payment_method'||'^'||'gl_account'||'^'||'object'||CHR(10));


    FOR REC_AP_EXTRACT IN CUR_AP_EXTRACT
    LOOP
      --UTL_FILE.PUT(LV_FILE_HANDLER,CHR(13)                                      ||CHR(10));
      UTL_FILE.PUT_LINE(LV_FILE_HANDLER,REC_AP_EXTRACT.AMOUNT||'^'||REC_AP_EXTRACT.payment_date||'^'||REC_AP_EXTRACT.payment_ref ||'^'||REC_AP_EXTRACT.currency_code||'^'||REC_AP_EXTRACT.remittance_msg||'^'||REC_AP_EXTRACT.supplier_num||'^'||REC_AP_EXTRACT.supplier_name||'^'||REC_AP_EXTRACT.payment_number||'^'||REC_AP_EXTRACT.company_code||'^'||REC_AP_EXTRACT.company||'^'||REC_AP_EXTRACT.pay_from_acct_num||'^'||REC_AP_EXTRACT.payment_method||'^'||REC_AP_EXTRACT.remittance_bank||'^'||REC_AP_EXTRACT.gl_acct||'^'||REC_AP_EXTRACT.object);
      --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,REC_AP_EXTRACT.AMOUNT ||';'||REC_AP_EXTRACT.payment_date||';'||REC_AP_EXTRACT.payment_ref ||';'||REC_AP_EXTRACT.currency_code||';'||REC_AP_EXTRACT.remittance_msg||';'||REC_AP_EXTRACT.supplier_num||';'||REC_AP_EXTRACT.supplier_name||';'||REC_AP_EXTRACT.payment_number||';'||REC_AP_EXTRACT.company_code||';'||REC_AP_EXTRACT.company||';'||REC_AP_EXTRACT.pay_from_acct_num||';'||REC_AP_EXTRACT.payment_method||';'||REC_AP_EXTRACT.remittance_bank||';'||REC_AP_EXTRACT.gl_acct||';'||REC_AP_EXTRACT.object);
    END LOOP;
  /*EXCEPTION
  WHEN NO_DATA_FOUND THEN
    FND_FILE.PUT_LINE(FND_FILE.LOG,'No Records Retrieved');
  END;*/
  utl_file.fflush(LV_FILE_HANDLER);
  UTL_FILE.FCLOSE(LV_FILE_HANDLER);

ELSE
FND_FILE.PUT_LINE(FND_FILE.LOG,'ZERO byte AP file generated');
END IF;
EXCEPTION
WHEN OTHERS THEN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Error in GENERATE_AP_EXTRACT : '||SQLERRM);
END GENERATE_AP_EXTRACT;
PROCEDURE GENERATE_GL_EXTRACT(
    PV_IN_ORG_ID       IN NUMBER,
    PV_IN_CURRENCY     IN VARCHAR2,
	  PV_IN_GL_ACCOUNT   IN VARCHAR2,
    PV_IN_GL_DATE_FROM IN VARCHAR2,
    PV_IN_GL_DATE_TO   IN VARCHAR2
    )
	IS
  LV_FILE_HANDLER UTL_FILE.FILE_TYPE;
  LV_DIR ALL_DIRECTORIES.DIRECTORY_PATH%TYPE := 'EPM_DIR_GEN_OUT';
  --LV_FILE_NAME VARCHAR2(240)                 := 'PB AR Extract For Bank Reconciliation_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24:MI:SS')||'.csv';
  --LV_FILE_NAME_AP VARCHAR2(240)                 := 'PB AP Extract For Bank Reconciliation_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24:MI:SS')||'.csv';
  LV_FILE_NAME VARCHAR2(240)                 := 'PB_GL_Extract_Bank_Recon_'||TO_CHAR(SYSDATE,'DDMMYYYYHH24MISS')||'.csv';
  LV_FROM_GL_DATE VARCHAR2(50) ;
  LV_TO_GL_DATE VARCHAR2(50) ;
  LV_IN_ORG_ID      NUMBER;
  LV_IN_CURRENCY     VARCHAR2(50);
  LV_IN_GL_ACCOUNT   VARCHAR2(50);
  LV_OUTPUT_HEADER VARCHAR2 (4000);
  LV_GL_COUNT NUMBER :=0;
  CURSOR CUR_GL_EXTRACT
  IS
/*select
       'amount' amount,
       'journal_date' journal_date,
       'currencycode' currencycode,
       'journal_number' journal_number,
       'company_code' company_code,
       'company' company,
       'gl_account' gl_account,
       'object' object
from dual
UNION ALL*/
select --gjh.name journal_name,
       --gjl.je_line_num journal_line_num,
       --gjl.accounted_dr journal_line_dr,
       --gjl.accounted_cr jounal_line_cr,
       NVL(gjl.accounted_dr,-gjl.accounted_cr) amount,
       to_date(gjh.date_created,'DD-MON-YYYY') journal_date,
       gjh.currency_code currencycode,
       gjh.doc_sequence_value journal_number,
       hou.short_code company_code,
       hou.name company,
       gcc.segment2 gl_account,
       gcc.segment8 object
from gl_je_headers gjh,
     gl_je_lines gjl,
     gl_code_combinations gcc,
     --gl_periods gp,
     HR_OPERATING_UNITS hou
where gjh.je_header_id=gjl.je_header_id
and gjh.ledger_id=gjl.ledger_id
and gjl.code_combination_id=gcc.code_combination_id
--and gjh.period_name=gp.period_name
and hou.set_of_books_id=gjh.ledger_id
--and hou.organization_id=1712
--and gjh.date_created between '01-AUG-2023' and '01-AUG-2023'
--AND gjh.currency_code='NOK'--NVL(LV_IN_CURRENCY,acr.currency_code)--NOK
--AND gcc.segment2='240200'--NVL(LV_IN_GL_ACCOUNT,gcc.segment2)
AND hou.organization_id=NVL(LV_IN_ORG_ID,hou.organization_id)--1712
AND gjh.currency_code=NVL(LV_IN_CURRENCY,gjh.currency_code)--NOK
AND gcc.segment2=NVL(LV_IN_GL_ACCOUNT,gcc.segment2)--240200
AND gjh.date_created BETWEEN fnd_date.canonical_to_date(LV_FROM_GL_DATE) AND fnd_date.canonical_to_date(LV_TO_GL_DATE)
order by gjh.date_created ,gjh.name, gjl.je_line_num
;

BEGIN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Starting XXCU_ARAPGL_EXTRACT_PKG.GENERATE_GL_EXTRACT procedure');
  FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_DIR:'||LV_DIR);
  FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_FILE_NAME:'||LV_FILE_NAME);
  FND_FILE.PUT_LINE(FND_FILE.LOG,'PV_IN_GL_DATE_FROM:'||PV_IN_GL_DATE_FROM);--PV_IN_GL_DATE_TO
  FND_FILE.PUT_LINE(FND_FILE.LOG,'PV_IN_GL_DATE_TO:'||PV_IN_GL_DATE_TO);--
  --LV_FILE_HANDLER := UTL_FILE.FOPEN(LV_DIR,LV_FILE_NAME, 'W', '32767');
  --FND_FILE.PUT_LINE(FND_FILE.LOG,'LV_FILE_HANDLER:'||LV_FILE_HANDLER);
  --FND_MESSAGE.SET_NAME ('XXCU', 'XXCU_GL_EXTRACT_HEADER');
  --LV_OUTPUT_HEADER := FND_MESSAGE.GET;
  --UTL_FILE.PUT(LV_FILE_HANDLER,LV_OUTPUT_HEADER);
  --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,LV_OUTPUT_HEADER);
  LV_TO_GL_DATE   :=  PV_IN_GL_DATE_TO ;
  LV_FROM_GL_DATE :=  PV_IN_GL_DATE_FROM ;
  LV_IN_ORG_ID       :=PV_IN_ORG_ID;
  LV_IN_CURRENCY     :=PV_IN_CURRENCY;
  LV_IN_GL_ACCOUNT   :=PV_IN_GL_ACCOUNT;
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Date From :'||LV_FROM_GL_DATE);--PV_IN_GL_DATE_FROM
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Date To :'  ||LV_TO_GL_DATE);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Org ID :'||LV_IN_ORG_ID);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'Currency Code :'  ||LV_IN_CURRENCY);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'GL Account :'||LV_IN_GL_ACCOUNT);
  FND_FILE.PUT_LINE (FND_FILE.LOG,'File Name :'||LV_FILE_NAME);


--  BEGIN
  
  BEGIN
  
  select COUNT(1)
  into LV_GL_COUNT
from gl_je_headers gjh,
     gl_je_lines gjl,
     gl_code_combinations gcc,
     --gl_periods gp,
     HR_OPERATING_UNITS hou
where gjh.je_header_id=gjl.je_header_id
and gjh.ledger_id=gjl.ledger_id
and gjl.code_combination_id=gcc.code_combination_id
--and gjh.period_name=gp.period_name
and hou.set_of_books_id=gjh.ledger_id
--and hou.organization_id=1712
--and gjh.date_created between '01-AUG-2023' and '01-AUG-2023'
--AND gjh.currency_code='NOK'--NVL(LV_IN_CURRENCY,acr.currency_code)--NOK
--AND gcc.segment2='240200'--NVL(LV_IN_GL_ACCOUNT,gcc.segment2)
AND hou.organization_id=NVL(LV_IN_ORG_ID,hou.organization_id)--1712
AND gjh.currency_code=NVL(LV_IN_CURRENCY,gjh.currency_code)--NOK
AND gcc.segment2=NVL(LV_IN_GL_ACCOUNT,gcc.segment2)--240200
AND gjh.date_created BETWEEN fnd_date.canonical_to_date(LV_FROM_GL_DATE) AND fnd_date.canonical_to_date(LV_TO_GL_DATE)
order by gjh.date_created ,gjh.name, gjl.je_line_num
;
FND_FILE.PUT_LINE(FND_FILE.LOG,'Total GL count :'||LV_GL_COUNT);
EXCEPTION
WHEN OTHERS THEN
FND_FILE.PUT_LINE(FND_FILE.LOG,'Error during GL count : '||SQLERRM);  
END;

IF LV_GL_COUNT>0 THEN
  --LV_OUTPUT_HEADER := 'amount'||';'||'journal_date'||';'||'currencycode'||';'||'journal_number'||';'||'company_code'||';'||'company'||';'||'gl_account'||';'||'object'";
  LV_FILE_HANDLER := UTL_FILE.FOPEN(LV_DIR,LV_FILE_NAME, 'W', '32767');
  UTL_FILE.PUT(LV_FILE_HANDLER,'amount'||'^'||'journal_date'||'^'||'currencycode'||'^'||'journal_number'||'^'||'company_code'||'^'||'company'||'^'||'gl_account'||'^'||'object'||CHR(10));

    FOR REC_GL_EXTRACT IN CUR_GL_EXTRACT
    LOOP
      --UTL_FILE.PUT(LV_FILE_HANDLER,CHR(13));
      UTL_FILE.PUT_LINE(LV_FILE_HANDLER,REC_GL_EXTRACT.amount||'^'||REC_GL_EXTRACT.journal_date ||'^'||REC_GL_EXTRACT.currencycode||'^'||REC_GL_EXTRACT.journal_number||'^'||REC_GL_EXTRACT.company||'^'||REC_GL_EXTRACT.company_code||'^'||REC_GL_EXTRACT.gl_account||'^'||REC_GL_EXTRACT.object);
      --FND_FILE.PUT_LINE(FND_FILE.OUTPUT,REC_GL_EXTRACT.amount||';'||REC_GL_EXTRACT.journal_date ||';'||';'||REC_GL_EXTRACT.currencycode||';'||REC_GL_EXTRACT.journal_number||';'||';'||REC_GL_EXTRACT.company||';'||REC_GL_EXTRACT.company_code||';'||REC_GL_EXTRACT.gl_account||';'||REC_GL_EXTRACT.object);
	  END LOOP;
  /*EXCEPTION
  WHEN NO_DATA_FOUND THEN
    FND_FILE.PUT_LINE(FND_FILE.LOG,'No Records Retrieved');
  END;*/
  utl_file.fflush(LV_FILE_HANDLER);
  UTL_FILE.FCLOSE(LV_FILE_HANDLER);

ELSE
FND_FILE.PUT_LINE(FND_FILE.LOG,'ZERO byte GL file generated');
END IF;

EXCEPTION
WHEN OTHERS THEN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Error in GENERATE_GL_EXTRACT : '||SQLERRM);
END GENERATE_GL_EXTRACT;

PROCEDURE MAIN(
    ERRBUF             OUT VARCHAR2,
    RETCODE            OUT VARCHAR2,
	  PV_IN_ORG_ID       IN NUMBER,
    PV_IN_CURRENCY     IN VARCHAR2,
	  PV_IN_GL_ACCOUNT   IN VARCHAR2,
    PV_IN_GL_DATE_FROM IN VARCHAR2,
    PV_IN_GL_DATE_TO   IN VARCHAR2,
    PV_SOURCE          IN VARCHAR2
	)
	IS

BEGIN

if PV_SOURCE='AR' then

FND_FILE.PUT_LINE(FND_FILE.LOG,'Inside AR extract');

GENERATE_AR_EXTRACT (PV_IN_ORG_ID,PV_IN_CURRENCY,PV_IN_GL_ACCOUNT,PV_IN_GL_DATE_FROM,PV_IN_GL_DATE_TO);

end if;
if PV_SOURCE='AP' then

FND_FILE.PUT_LINE(FND_FILE.LOG,'Inside AP extract');

GENERATE_AP_EXTRACT (PV_IN_ORG_ID,PV_IN_CURRENCY,PV_IN_GL_ACCOUNT,PV_IN_GL_DATE_FROM,PV_IN_GL_DATE_TO);

end if;

if PV_SOURCE ='GL' then

FND_FILE.PUT_LINE(FND_FILE.LOG,'Inside GL extract');

GENERATE_GL_EXTRACT (PV_IN_ORG_ID,PV_IN_CURRENCY,PV_IN_GL_ACCOUNT,PV_IN_GL_DATE_FROM,PV_IN_GL_DATE_TO);

end if;

if PV_SOURCE is null then
FND_FILE.PUT_LINE(FND_FILE.LOG,'Inside AR AP and GL extract');

GENERATE_AR_EXTRACT (PV_IN_ORG_ID,PV_IN_CURRENCY,PV_IN_GL_ACCOUNT,PV_IN_GL_DATE_FROM,PV_IN_GL_DATE_TO);
GENERATE_AP_EXTRACT (PV_IN_ORG_ID,PV_IN_CURRENCY,PV_IN_GL_ACCOUNT,PV_IN_GL_DATE_FROM,PV_IN_GL_DATE_TO);
GENERATE_GL_EXTRACT (PV_IN_ORG_ID,PV_IN_CURRENCY,PV_IN_GL_ACCOUNT,PV_IN_GL_DATE_FROM,PV_IN_GL_DATE_TO);

--end if;
--end if;
end if;

RETCODE := 0; -- Retcode for Normal completion
EXCEPTION
WHEN OTHERS THEN
  FND_FILE.PUT_LINE(FND_FILE.LOG,'Error in GENERATE File : '||SQLERRM);
end main;
END XXCU_ARAPGL_EXTRACT_PKG;