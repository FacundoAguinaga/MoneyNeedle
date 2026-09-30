"""Tests de la lógica pura (sin modelo, sin GPU). Correr: python -m unittest test_mn_parse."""
import unittest

from mn_parse import (detect_currency, extract_call, find_word_numbers,
                      for_model, keyword_category, numbers_in_query,
                      parse_number_token, words_to_number)


class TestParseNumberToken(unittest.TestCase):
    def test_miles_con_punto(self):
        self.assertEqual(parse_number_token("35.000"), 35000)
        self.assertEqual(parse_number_token("1.200.000"), 1200000)
        self.assertEqual(parse_number_token("8.400"), 8400)

    def test_decimal_con_punto(self):
        self.assertAlmostEqual(parse_number_token("10.50"), 10.5)

    def test_coma_decimal_y_miles(self):
        self.assertAlmostEqual(parse_number_token("10,50"), 10.5)
        self.assertEqual(parse_number_token("8,400"), 8400)
        self.assertAlmostEqual(parse_number_token("1.200,50"), 1200.5)

    def test_simple(self):
        self.assertEqual(parse_number_token("5000"), 5000)


class TestNumbersInQuery(unittest.TestCase):
    def test_digitos(self):
        self.assertIn(8000.0, numbers_in_query("taxi 8000 ayer"))

    def test_k_y_lucas(self):
        self.assertIn(200000.0, numbers_in_query("me pagaron 200k"))
        self.assertIn(5000.0, numbers_in_query("5 lucas en súper"))

    def test_mil_solo_y_millones(self):
        self.assertIn(1000.0, numbers_in_query("pague mil en impuestos"))
        self.assertIn(200000.0, numbers_in_query("compre 200 mil en ropa"))
        self.assertIn(2000000.0, numbers_in_query("gasté 2 millones"))

    def test_miles_con_punto(self):
        self.assertIn(290000.0, numbers_in_query("pagué 290.000 del alquiler"))

    def test_decimales(self):
        self.assertIn(10.5, numbers_in_query("pagé 10.50 de café"))

    def test_palabras(self):
        self.assertIn(5000.0, numbers_in_query("gaste cinco mil"))
        self.assertIn(200000.0, numbers_in_query("doscientos mil del sueldo"))


class TestFindWordNumbers(unittest.TestCase):
    def test_span(self):
        spans = find_word_numbers("gaste cinco mil en súper")
        self.assertEqual(len(spans), 1)
        s, e, v = spans[0]
        self.assertEqual(v, 5000)
        self.assertIn("cinco mil", f"gaste cinco mil en súper"[s:e])

    def test_sin_numeros(self):
        self.assertEqual(find_word_numbers("hola qué hora es"), [])


class TestKeywordCategory(unittest.TestCase):
    def test_no_substring(self):
        # "gas" no debe matchear dentro de "gaste"
        self.assertNotEqual(keyword_category("gaste 1000000 en el auto"), "servicios")

    def test_match_real(self):
        self.assertEqual(keyword_category("pagué el gas"), "servicios")
        self.assertEqual(keyword_category("taxi 8000"), "transporte")
        self.assertEqual(keyword_category("obra social 5000"), "salud")

    def test_none(self):
        self.assertIsNone(keyword_category("hola qué tal"))


class TestCurrencyAndModel(unittest.TestCase):
    def test_detect(self):
        self.assertEqual(detect_currency("perfume de 100 usd"), "USD")
        self.assertEqual(detect_currency("50 dólares"), "USD")
        self.assertEqual(detect_currency("gasté 5000"), "ARS")

    def test_for_model_saca_moneda(self):
        self.assertEqual(for_model("gaste 100 usd en netflix"), "gaste 100 en netflix")
        # si quedara vacío, devuelve el original
        self.assertEqual(for_model("usd"), "usd")


class TestExtractCall(unittest.TestCase):
    def test_suppressed(self):
        r = {"function_calls": [], "suppressed_calls": [{"name": "t", "arguments": {}}]}
        self.assertEqual(extract_call(r)["name"], "t")

    def test_vacio_y_none(self):
        self.assertIsNone(extract_call({"function_calls": [], "suppressed_calls": []}))
        self.assertIsNone(extract_call(None))


if __name__ == "__main__":
    unittest.main()
