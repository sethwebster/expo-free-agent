import { useTheme } from '../hooks/useTheme';

export function ThemeToggle() {
  const { theme, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      className="relative w-8 h-8 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors flex items-center justify-center group"
      aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
      title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
    >
      {/* Sun icon - shown in dark mode */}
      <svg
        className={`absolute w-5 h-5 transition-all duration-300 ${theme === 'dark'
            ? 'opacity-100 rotate-0 scale-100'
            : 'opacity-0 rotate-90 scale-0'
          }`}
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <circle cx="12" cy="12" r="4" className="stroke-yellow-400" strokeWidth="2" />
        <path
          className="stroke-yellow-400"
          strokeLinecap="round"
          strokeWidth="2"
          d="M12 2v2m0 16v2M4.93 4.93l1.41 1.41m11.32 11.32l1.41 1.41M2 12h2m16 0h2M4.93 19.07l1.41-1.41m11.32-11.32l1.41-1.41"
        />
      </svg>

      {/* Moon icon - shown in light mode */}
      <svg
        className={`absolute w-5 h-5 transition-all duration-300 ${theme === 'light'
            ? 'opacity-100 rotate-0 scale-100'
            : 'opacity-0 -rotate-90 scale-0'
          }`}
        fill="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          className="fill-indigo-600"
          d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"
        />
      </svg>
    </button>
  );
}
