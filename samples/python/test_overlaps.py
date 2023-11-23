from datetime import datetime

from django.test import TestCase
from django.utils.timezone import utc


class OverlapTests(TestCase):
    def verify(self, implementation):
        def make_datetime(hour, minute):
            return datetime(2021, 1, 1, hour, minute, tzinfo=utc)

        existing_start = make_datetime(14, 00)
        existing_end = make_datetime(15, 00)

        cases = {
            "new matches existing": {
                "new_start": make_datetime(14, 00),
                "new_end": make_datetime(15, 00),
                "overlaps": True,
            },
            "new contains existing": {
                "new_start": make_datetime(13, 45),
                "new_end": make_datetime(15, 15),
                "overlaps": True,
            },
            "existing contains new": {
                "new_start": make_datetime(14, 15),
                "new_end": make_datetime(14, 45),
                "overlaps": True,
            },
            "new starts when existing ends": {
                "new_start": make_datetime(15, 00),
                "new_end": make_datetime(16, 00),
                "overlaps": False,
            },
            "new ends when existing starts": {
                "new_start": make_datetime(13, 00),
                "new_end": make_datetime(14, 00),
                "overlaps": False,
            },
            "new overlaps existing start": {
                "new_start": make_datetime(13, 30),
                "new_end": make_datetime(14, 30),
                "overlaps": True,
            },
            "new overlaps existing end": {
                "new_start": make_datetime(14, 30),
                "new_end": make_datetime(15, 30),
                "overlaps": True,
            },
            "existing contains new with matching start": {
                "new_start": make_datetime(14, 00),
                "new_end": make_datetime(14, 30),
                "overlaps": True,
            },
            "existing contains new with matching end": {
                "new_start": make_datetime(14, 30),
                "new_end": make_datetime(15, 00),
                "overlaps": True,
            },
            "new contains existing with matching start": {
                "new_start": make_datetime(14, 00),
                "new_end": make_datetime(15, 30),
                "overlaps": True,
            },
            "new contains existing with matching end": {
                "new_start": make_datetime(13, 30),
                "new_end": make_datetime(15, 00),
                "overlaps": True,
            },
            "new is before existing": {
                "new_start": make_datetime(12, 00),
                "new_end": make_datetime(13, 00),
                "overlaps": False,
            },
            "new is after existing": {
                "new_start": make_datetime(16, 00),
                "new_end": make_datetime(17, 00),
                "overlaps": False,
            },
        }

        for (name, case) in cases.items():
            with self.subTest(name):
                self.assertEqual(
                    case["overlaps"],
                    implementation(
                        existing_start=existing_start,
                        existing_end=existing_end,
                        new_start=case["new_start"],
                        new_end=case["new_end"],
                    ),
                )

    def test_jason(self):
        def implementation(existing_start, existing_end, new_start, new_end):
            return (
                existing_start <= new_start < existing_end
                or existing_start < new_end <= existing_end
            )

        self.verify(implementation)

    def test_hasnat(self):
        def implementation(existing_start, existing_end, new_start, new_end):
            return (
                existing_start <= new_start < existing_end
                or existing_start < new_end <= existing_end
                or (existing_start >= new_start and existing_end <= new_end)
            )

        self.verify(implementation)

    def test_nico(self):
        def implementation(existing_start, existing_end, new_start, new_end):
            return new_start < existing_end and existing_start < new_end

        self.verify(implementation)
