from datetime import datetime
from decimal import Decimal

from app.sms_parser import parse_sms


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


def test_otp_is_ignored():
    parsed = parse_sms("Your OTP is 482193. Do not share it.")
    assert not parsed.recognized
    assert parsed.reason == "otp"


def test_plain_chat_is_ignored():
    parsed = parse_sms("See you at 7")
    assert not parsed.recognized
