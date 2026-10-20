import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

spec = importlib.util.spec_from_file_location("server", Path(__file__).parents[1] / "app/server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.httpd.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join()

    def get(self, path):
        return urllib.request.urlopen(self.base + path)

    def test_liveness_without_secret(self):
        with self.get('/healthz') as response:
            self.assertEqual(response.status, 200)

    def test_readiness_and_no_secret_disclosure(self):
        with tempfile.TemporaryDirectory() as directory:
            server.SECRET_PATH = Path(directory) / 'demo-message'
            with self.assertRaises(urllib.error.HTTPError) as error:
                self.get('/readyz')
            self.assertEqual(error.exception.code, 503)
            server.SECRET_PATH.write_text('sensitive-test-value')
            with self.get('/readyz') as response:
                self.assertEqual(response.status, 200)
            with self.get('/') as response:
                body = response.read().decode()
                self.assertTrue(json.loads(body)['secret_mounted'])
                self.assertNotIn('sensitive-test-value', body)

    def test_prometheus_metric(self):
        with self.get('/metrics') as response:
            self.assertIn(b'http_requests_total', response.read())

    def test_unknown_endpoint(self):
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.get('/missing')
        self.assertEqual(error.exception.code, 404)

if __name__ == '__main__':
    unittest.main()
