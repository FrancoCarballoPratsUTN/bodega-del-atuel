import pytest

from bodega_api.errors import http_status_for_sqlstate


@pytest.mark.parametrize(
    ("sqlstate", "expected_status"),
    [
        ("23502", 422),
        ("23503", 409),
        ("23505", 409),
        ("23514", 422),
        ("22P02", 400),
        ("P0001", 409),
        ("40001", 503),
        ("40P01", 503),
        ("XX000", 500),
    ],
)
def test_sqlstate_mapping(sqlstate, expected_status):
    assert http_status_for_sqlstate(sqlstate) == expected_status


def test_unknown_sqlstate_defaults_to_internal_error():
    assert http_status_for_sqlstate(None) == 500
