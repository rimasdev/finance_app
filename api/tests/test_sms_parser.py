from datetime import date, datetime
from decimal import Decimal

from app.sms_parser import parse_sms, parse_utility


def test_debit_with_merchant_and_balance():
    text = (
        "Dear Customer, your A/c XX8741 has been debited with Rs.4,100.00 "
        "on 29/09/2026 02:11. Info: REGISTER.LK. Avl Bal: Rs.12,345.67"
    )
    parsed = parse_sms(text)
    assert parsed.recognized
    assert parsed.direction == "expense"
    assert parsed.amount == 4100
    assert parsed.last4 == "8741"
    assert parsed.merchant == "REGISTER.LK"
    assert parsed.balance == Decimal("12345.67")
    assert parsed.occurred_at == datetime(2026, 9, 29, 2, 11)


def test_atm_withdrawal():
    text = "Rs.5,000.00 withdrawn from ATM. A/c **8741 on 29-Sep-2026 08:56. Bal Rs.7,345.67"
    parsed = parse_sms(text)
    assert parsed.direction == "expense"
    assert parsed.amount == 5000
    assert parsed.last4 == "8741"
    assert parsed.merchant == "ATM withdrawal"
    assert parsed.withdrawal is True
    assert parsed.category_hint is None


def test_salary_credit():
    text = (
        "LKR 85,000.00 has been credited to your Acct ****2214 on 28/09/2026. "
        "Info: SALARY ACME. Avl Bal LKR 90,000.00"
    )
    parsed = parse_sms(text)
    assert parsed.direction == "income"
    assert parsed.amount == 85000
    assert parsed.last4 == "2214"
    assert parsed.merchant == "SALARY ACME"
    assert parsed.category_hint == "Salary"


def test_shopping_hint():
    text = "Purchase of Rs. 1,250.00 at KEELLS on 29/09/2026 from card 8028"
    parsed = parse_sms(text)
    assert parsed.direction == "expense"
    assert parsed.last4 == "8028"
    assert parsed.category_hint == "Shopping"


def test_combank_card_purchase_and_withdrawal():
    purchase = parse_sms(
        "Dear Cardholder, Purchase at Kids Mania Kandy LK for LKR 490.00 on "
        "01/10/26 04:00 PM has been authorised on your debit card ending #9383."
    )
    assert purchase.recognized
    assert purchase.direction == "expense"
    assert purchase.amount == Decimal("490.00")
    assert purchase.last4 == "9383"
    assert purchase.merchant == "Kids Mania Kandy"
    assert purchase.category_hint == "Shopping"
    assert purchase.withdrawal is False
    assert purchase.occurred_at == datetime(2026, 10, 1, 16, 0)

    withdrawal = parse_sms(
        "Withdrawal at PABC_Katugasthota-----Katugasthota- LK for LKR 4,000.00 "
        "on 01/10/26 04:13 PM from card ending #9383."
    )
    assert withdrawal.direction == "expense"
    assert withdrawal.amount == Decimal("4000.00")
    assert withdrawal.last4 == "9383"
    assert "PABC" in (withdrawal.merchant or "")
    assert withdrawal.withdrawal is True
    assert withdrawal.category_hint is None
    bakers = parse_sms("Purchase at RICORN BAKERS LK for LKR 490.00 on 01/10/26 from card ending #9383.")
    assert bakers.category_hint == "Dining out"
    lovers = parse_sms("Purchase at Lovers Point Katugastota LK for LKR 550.00 on 01/10/26 from card ending #9383.")
    assert lovers.category_hint == "Dining out"


def test_declined_card_message_is_ignored():
    parsed = parse_sms(
        "Dear Cardholder, your card was declined due to insufficient funds. "
        "The attempted transaction amount was USD 17.29 at NEVERCODE LTD on 01/10/26 03:32 PM."
    )
    assert not parsed.recognized
    assert parsed.reason == "declined"


def test_otp_is_ignored():
    parsed = parse_sms("Your OTP is 482193. Do not share it.")
    assert not parsed.recognized
    assert parsed.reason == "otp"


def test_plain_chat_is_ignored():
    parsed = parse_sms("See you at 7")
    assert not parsed.recognized


def test_an_electricity_bill_records_the_outstanding_and_due_date():
    text = """A/C No: 8021065206 (D1)
M.F.R. MOHAMED.

B/F: Rs. 24,825.28
Payments: Rs. 12,500.00
Debits: Rs. 112.98
Outstanding: Rs. 12,438.26 by 2026-10-04

Reading Date: 2026-10-11 (458)
Reading: 11173 - 11005 = 168 Units
Charge: Rs. 5,692.00
SSC Levy: Rs. 145.95
Monthly Bill: Rs. 5,837.95

Total Due: Rs. 18,276.21

View e-Bill here:
https://ebill.edl.lk/v1/example
"""
    bill = parse_utility(text)
    assert bill is not None
    assert bill.kind == "bill"
    assert bill.provider == "Electricity"
    assert bill.account_no == "8021065206"
    assert bill.holder == "M.F.R. MOHAMED"
    assert bill.outstanding == Decimal("12438.26")
    assert bill.due_on == date(2026, 10, 4)
    assert bill.monthly == Decimal("5837.95")
    assert bill.total_due == Decimal("18276.21")
    parsed = parse_sms(text)
    assert not parsed.recognized
    assert parsed.reason == "utility_bill"


def test_an_nwsdb_bill_records_the_latest_total_due():
    text = """*** NOTICE OF DISCONNECTION ***
Please Settle Rs : 5896.32 Within 2 Days from the date of issuance.Otherwise supply will be disconnected.

Bill Ref : 2026/10
A/C No : 42/12/138/027/11 (10)
MR. M.J.M. FLYIL

Balance B/F (Rs) : 5896.32
Period : 01-08-2026 to 01-09-2026
Monthly Charges : Rs. 3254.83
Total Due : Rs. 5896.32

Period : 01-09-2026 to 01-10-2026
Water Charge (Before Taxes) (Rs) : 2650.00
Monthly Charges : Rs. 3204.93
Total Due : Rs. 9101.25

pl. settle within 14 days to earn rebate,
NWSDB
https://ebis.waterboard.lk/ebill/?key=onxaZJ0f3w
"""
    bill = parse_utility(text)
    assert bill is not None
    assert bill.kind == "bill"
    assert bill.provider == "Water"
    assert bill.account_no == "42/12/138/027/11"
    assert bill.holder == "MR. M.J.M. FLYIL"
    assert bill.outstanding == Decimal("9101.25")
    assert bill.total_due == Decimal("9101.25")
    assert bill.monthly == Decimal("3204.93")
    assert bill.due_on == date(2026, 10, 15)
    parsed = parse_sms(text)
    assert not parsed.recognized
    assert parsed.reason == "utility_bill"
    notice = parse_utility(
        "*** NOTICE OF DISCONNECTION ***\nPlease Settle Rs : 5896.32 Within 2 Days from the date of issuance."
        "Otherwise supply will be disconnected."
    )
    assert notice is not None
    assert notice.kind == "notice"


def test_a_phone_bill_is_a_utility_and_a_dialog_debit_is_phone():
    text = """HUTCH Bill for 94725742238
Invoice Period: 01-09-26 to 30-09-26
Amount Due: Rs. 1890.00
Please pay before 15-10-2026
"""
    bill = parse_utility(text)
    assert bill is not None
    assert bill.kind == "bill"
    assert bill.provider == "Hutch"
    assert bill.account_no == "94725742238"
    assert bill.outstanding == Decimal("1890.00")
    assert bill.due_on == date(2026, 10, 15)
    assert parse_sms(text).reason == "utility_bill"
    debit = parse_sms("LKR 2,000.00 debited from A/c XX3390 on 02/09/2026. Info: DIALOG")
    assert debit.recognized
    assert debit.category_hint == "Phone"
    power = parse_sms("Rs. 500.00 debited. Info: LECO")
    assert power.category_hint == "Electricity"


def test_a_water_notice_and_a_payment_receipt_are_not_transactions():
    notice = "A/C No 42/12/138/027/11, Dear Customer, Water supply of your area will be interrupted from 2026.09.25."
    parsed_notice = parse_utility(notice)
    assert parsed_notice is not None
    assert parsed_notice.kind == "notice"
    assert not parse_sms(notice).recognized
    receipt = (
        "Dear customer, we have received your payment of Rs.6000.0 for "
        "account number 42/12/138/027/11 from COM BANK on 2026-10-02, Thank you - NWSDB"
    )
    parsed_receipt = parse_utility(receipt)
    assert parsed_receipt is not None
    assert parsed_receipt.kind == "payment"
    assert parsed_receipt.account_no == "42/12/138/027/11"
    assert not parse_sms(receipt).recognized
