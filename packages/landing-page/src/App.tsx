import "./styles/globals.css";

export default function App() {
  return (
    <div className="min-h-screen bg-white dark:bg-black text-zinc-900 dark:text-zinc-100">
      <Hero />
      <BentoGrid />
      <HowItWorks />
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

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 auto-rows-[400px]">
          {/* Card 1: CPU (Large) */}
          <BentoCard
            colSpan="md:col-span-2"
            title="Idle Compute."
            subtitle="Your Mac sleeps while you grab coffee. Put that M-series chip to work."
            image="/assets/feature-cpu.png"
            dark
          />

          {/* Card 2: Security (Tall) */}
          <BentoCard
            colSpan="md:col-span-1"
            title="VM Isolated."
            subtitle="Hypervisor safety."
            image="/assets/feature-security.png"
          />

          {/* Card 3: Network (Full Width) */}
          <BentoCard
            colSpan="md:col-span-3"
            title="Community Mesh."
            subtitle="No servers to manage. No cloud bills. Just a peer-to-peer build network built by Expo developers just like you."
            image="/assets/feature-network.png"
            align="center"
          />
        </div>
      </div>
    </section>
  );
}

function BentoCard({
  colSpan,
  title,
  subtitle,
  image,
  dark,
  align = "left"
}: {
  colSpan: string;
  title: string;
  subtitle: string;
  image: string;
  dark?: boolean;
  align?: "left" | "center";
}) {
  return (
    <div
      className={`relative group overflow-hidden rounded-[2rem] border border-zinc-200 dark:border-zinc-800 ${colSpan} ${dark ? 'bg-black text-white' : 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white'} hover:shadow-2xl transition-shadow duration-300`}
    >
      <div className="absolute inset-0 z-0 overflow-hidden">
        <img
          src={image}
          className="w-full h-full object-cover opacity-90 group-hover:scale-105 transition-transform duration-1000 ease-out"
          alt={title}
        />
        <div className={`absolute inset-0 bg-gradient-to-t ${dark ? 'from-black via-black/40 to-transparent' : 'from-white via-white/40 to-transparent dark:from-black dark:via-black/40'}`} />
      </div>

      <div className={`relative z-10 h-full flex flex-col justify-end p-10 ${align === 'center' ? 'items-center text-center' : 'items-start'}`}>
        <h3 className="text-4xl md:text-5xl font-semibold tracking-tighter mb-4 drop-shadow-sm">{title}</h3>
        <p className={`text-xl font-medium max-w-xl ${dark ? 'text-zinc-400' : 'text-zinc-600 dark:text-zinc-300'} drop-shadow-sm`}>{subtitle}</p>
      </div>
    </div>
  );
}

function HowItWorks() {
  return (
    <section id="how-it-works" className="py-32 bg-zinc-50 dark:bg-black px-6">
      <div className="max-w-[980px] mx-auto">
        <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-24 text-center">
          The Ecosystem.
        </h2>

        <div className="space-y-32 relative">
          {/* Connecting line */}
          <div className="absolute left-[2.4rem] top-8 bottom-8 w-0.5 bg-zinc-200 dark:bg-zinc-800 md:left-1/2 md:-ml-[1px]" />

          <Step
            num="01"
            title="The Controller"
            desc="The centralized brain of the operation. It manages the queue, tracks credits, and dispatches jobs to workers."
            side="left"
          />
          <Step
            num="02"
            title="The Worker"
            desc="A lightweight macOS menu bar app. It listens for jobs, spins up a fresh VM, runs the build, and shuts down."
            side="right"
          />
          <Step
            num="03"
            title="The CLI"
            desc="Submit builds from your terminal. 'free-agent build --ios'. Your credits permit are checked, your build is shipped."
            side="left"
          />
        </div>
      </div>
    </section>
  );
}

function Step({ num, title, desc, side }: { num: string; title: string; desc: string; side: "left" | "right" }) {
  return (
    <div className="relative flex flex-col md:flex-row gap-12 items-start">
      {/* Timeline Dot */}
      <div className="absolute left-[1.9rem] top-10 w-4 h-4 rounded-full bg-zinc-900 dark:bg-white ring-4 ring-white dark:ring-black md:left-1/2 md:-ml-2 z-10" />

      <div className={`flex-1 ${side === 'right' ? 'md:order-last md:pl-16' : 'md:text-right md:pr-16'} pl-20 md:pl-0`}>
        <div className="text-8xl font-bold text-zinc-200 dark:text-zinc-900 tracking-tighter absolute -top-10 -z-10 select-none opacity-50">{num}</div>
        <h3 className="text-3xl font-semibold mb-4">{title}</h3>
        <p className="text-xl md:text-2xl text-zinc-500 font-medium leading-relaxed tracking-tight text-balance">{desc}</p>
      </div>
      <div className="hidden md:block flex-1" />
    </div>
  );
}
