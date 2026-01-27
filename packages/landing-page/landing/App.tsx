import "./styles.css";

export default function App() {
  return (
    <div className="min-h-screen bg-white dark:bg-black text-zinc-900 dark:text-zinc-100">
      <Hero />
      <BentoGrid />
    </div>
  );
}

function Hero() {
  return (
    <section className="relative h-screen flex flex-col justify-center overflow-hidden">
      {/* Static Background - no scroll effects */}
      <div className="fixed inset-0 z-0 pointer-events-none">
        <img
          src="/assets/hero-bg-large.png"
          alt="Background"
          className="w-full h-full object-cover opacity-80 dark:opacity-30"
        />
        {/* Bottom fade gradient */}
        <div className="absolute inset-x-0 bottom-0 h-64 bg-gradient-to-t from-white dark:from-black to-transparent" />
        {/* Top nav gradient */}
        <div className="absolute inset-x-0 top-0 h-32 bg-gradient-to-b from-white/90 dark:from-black/90 to-transparent" />
      </div>

      {/* Content */}
      <div className="relative max-w-[1200px] mx-auto text-center w-full z-10 px-6 pt-20">
        <div className="inline-block mb-6 px-4 py-1.5 rounded-full border border-black/5 dark:border-white/10 bg-white/40 dark:bg-black/40 backdrop-blur-md text-[11px] font-semibold uppercase tracking-widest text-zinc-600 dark:text-zinc-400">
          Open Source • Distributed • Secure
        </div>

        <h1 className="text-7xl md:text-9xl lg:text-[10rem] font-bold tracking-tighter mb-8 leading-[0.85] text-zinc-900 dark:text-white flex flex-col items-center">
          <span>Distributed.</span>
          <span className="flex items-center justify-center mt-2">
            {"Unlimited.".split("").map((char, i) => (
              <span key={i} className="inline-block">
                <span
                  className="inline-block animate-letter-rise bg-clip-text text-transparent pb-4 bg-[linear-gradient(8deg,rgba(79,70,229,0.5)_0%,rgba(129,140,248,0.8)_50%,rgba(79,70,229,0.5)_100%)]"
                  style={{
                    animationDelay: `${500 + i * 75}ms`
                  }}
                >
                  {char}
                </span>
              </span>
            ))}
          </span>
        </h1>

        <p className="text-2xl md:text-3xl font-medium text-zinc-600 dark:text-zinc-300 max-w-2xl mx-auto mb-12">
          Turn your idle Mac into build credits.
          <br className="hidden md:block" />
          Build your Expo apps for free.
        </p>

        <div className="flex flex-col sm:flex-row items-center justify-center gap-5">
          <a href="#get-started" className="px-10 py-5 rounded-full bg-zinc-900 dark:bg-white text-white dark:text-black text-xl font-bold">
            Start Earning
          </a>
          <a href="#how-it-works" className="px-10 py-5 rounded-full bg-white/50 dark:bg-black/50 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-white text-xl font-bold">
            How it works
          </a>
        </div>
      </div>
    </section>
  );
}

function BentoGrid() {
  return (
    <section id="features" className="pt-32 pb-32 bg-white dark:bg-black relative z-10">
      <div className="max-w-[1200px] mx-auto px-6">
        <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-4 text-center">
          Power in numbers.
        </h2>
        <p className="text-xl text-zinc-500 text-center max-w-2xl mx-auto mb-16">
          A decentralized architecture designed for privacy, speed, and fairness.
        </p>
        <div className="h-96 bg-zinc-100 dark:bg-zinc-900 rounded-3xl flex items-center justify-center text-zinc-400">
          Bento Grid Placeholder
        </div>
      </div>
    </section>
  );
}
