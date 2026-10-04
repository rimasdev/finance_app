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
