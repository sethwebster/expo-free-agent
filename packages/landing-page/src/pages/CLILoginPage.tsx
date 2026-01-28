import { useState, FormEvent } from 'react';

const DEMO_API_KEY = 'test-api-key-demo-1234567890';

export function CLILoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    setIsLoading(true);

    // For demo: accept any credentials
    // Encode API key as base64
    const token = btoa(DEMO_API_KEY);

    // Get callback URL from query params
    const params = new URLSearchParams(window.location.hash.split('?')[1] || '');
    const callback = params.get('callback');

    if (callback) {
      // SECURITY: Validate callback URL to prevent open redirect attacks
      try {
        const url = new URL(callback);
        if (url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
          alert('Invalid callback URL: must be localhost');
          setIsLoading(false);
          return;
        }
        // Redirect to validated callback with token
        window.location.href = `${callback}?token=${token}`;
      } catch {
        alert('Invalid callback URL');
        setIsLoading(false);
      }
    } else {
      // Fallback: show error
      alert('No callback URL provided');
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-white dark:bg-black flex items-center justify-center px-6">
      <div className="w-full max-w-md">
        {/* Expo Logo */}
        <div className="flex justify-center mb-8">
          <svg
            width="48"
            height="48"
            viewBox="0 0 48 48"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
            className="text-zinc-900 dark:text-white"
          >
            <path
              d="M24 0C10.745 0 0 10.745 0 24s10.745 24 24 24 24-10.745 24-24S37.255 0 24 0zm0 43.636C13.155 43.636 4.364 34.845 4.364 24S13.155 4.364 24 4.364 43.636 13.155 43.636 24 34.845 43.636 24 43.636z"
              fill="currentColor"
            />
            <path
              d="M24 8.727c-8.431 0-15.273 6.842-15.273 15.273S15.569 39.273 24 39.273 39.273 32.431 39.273 24 32.431 8.727 24 8.727zm0 26.182c-6.016 0-10.909-4.893-10.909-10.909S17.984 13.091 24 13.091 34.909 17.984 34.909 24 30.016 34.909 24 34.909z"
              fill="currentColor"
            />
          </svg>
        </div>

        {/* Heading */}
        <h1 className="text-3xl font-bold text-center mb-2 text-zinc-900 dark:text-white">
          Log in to Expo
        </h1>
        <p className="text-center text-zinc-500 dark:text-zinc-400 mb-8">
          Continue to Expo Free Agent
        </p>

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Email Input */}
          <div>
            <label
              htmlFor="email"
              className="block text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-2"
            >
              Email or username
            </label>
            <input
              id="email"
              type="text"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="your@email.com"
              required
              className="w-full px-4 py-3 rounded-lg border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
            />
          </div>

          {/* Password Input */}
          <div>
            <label
              htmlFor="password"
              className="block text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-2"
            >
              Password
            </label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              required
              className="w-full px-4 py-3 rounded-lg border border-zinc-300 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
            />
          </div>

          {/* Submit Button */}
          <button
            type="submit"
            disabled={isLoading}
            className="w-full px-6 py-3 rounded-lg bg-indigo-600 hover:bg-indigo-700 disabled:bg-indigo-400 text-white font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-black"
          >
            {isLoading ? 'Logging in...' : 'Continue'}
          </button>
        </form>

        {/* Footer Links */}
        <div className="mt-6 text-center text-sm text-zinc-500 dark:text-zinc-400">
          <a
            href="https://expo.dev"
            className="hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors"
          >
            Forgot password?
          </a>
          <span className="mx-2">•</span>
          <a
            href="https://expo.dev"
            className="hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors"
          >
            Create account
          </a>
        </div>

        {/* Demo Notice */}
        <div className="mt-8 p-4 rounded-lg bg-zinc-100 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800">
          <p className="text-xs text-zinc-600 dark:text-zinc-400 text-center">
            <strong>Demo Mode:</strong> Any credentials will work for this preview.
          </p>
        </div>
      </div>
    </div>
  );
}
