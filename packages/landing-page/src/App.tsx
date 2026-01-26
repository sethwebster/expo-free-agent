import { useRef, useEffect, useState } from "react";
import { ThemeToggle } from "./components/ThemeToggle";

import { NetworkHUD } from "./components/NetworkHUD";

// Hook for scroll animations with optional delay
function useScrollReveal(delay = 0) {
  const ref = useRef<HTMLDivElement>(null);
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsVisible(true);
          observer.disconnect(); // Only animate once
        }
      },
      { threshold: 0.1, rootMargin: "0px 0px -50px 0px" }
    );

    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);

  return { ref, isVisible, delay };
}

export default function App() {
  return (
    <div className="min-h-screen bg-white dark:bg-black overflow-x-hidden selection:bg-indigo-500/30 font-sans text-zinc-900 dark:text-zinc-100 transition-colors duration-500">
      <Nav />
      <Hero />
      <BentoGrid />
      <HowItWorks />
      <GetStarted />
      <Footer />
    </div>
  );
}

function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return (
    <nav
      className={`fixed top-0 inset-x-0 z-50 h-14 transition-all duration-500 border-b ${scrolled
        ? "bg-white/70 dark:bg-black/70 backdrop-blur-md border-zinc-200/50 dark:border-zinc-800/50"
        : "bg-transparent border-transparent"
        }`}
    >
      <div className="max-w-[1000px] mx-auto h-full px-6 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="w-5 h-5 rounded bg-zinc-900 dark:bg-white animate-pulse" />
          <span className="font-semibold tracking-tight text-sm text-zinc-900 dark:text-white">Free Agent</span>
        </div>
        <div className="flex items-center gap-6 text-xs font-medium text-zinc-600 dark:text-zinc-400">
          <a href="#features" className="hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors">Overview</a>
          <a href="#how-it-works" className="hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors">Process</a>
          <ThemeToggle />
          <a
            href="https://github.com/expo/expo-free-agent"
            className="px-3 py-1 bg-zinc-900 dark:bg-white text-white dark:text-black rounded-full hover:scale-105 transition-transform"
            target="_blank"
            rel="noopener noreferrer"
          >
            GitHub
          </a>
        </div>
      </div>
    </nav>
  );
}

function Hero() {
  const { ref, isVisible } = useScrollReveal();
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => {
      requestAnimationFrame(() => setScrollY(window.scrollY));
    };
    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  // Opacity: fades out completely by the time user scrolls 100vh (approx 900px)
  const opacity = Math.max(0, 1 - scrollY / window.innerHeight);
  // Scale: subtle zoom in as user scrolls down
  const scale = 1.05 + scrollY * 0.0002;

  return (
    <section className="relative h-screen flex flex-col justify-center overflow-hidden">
      {/* Immersive Fixed Background - Parallax Effect */}
      <div
        className="fixed inset-0 z-0 select-none pointer-events-none w-full h-full will-change-opacity"
        style={{ opacity }}
      >
        <img
          src="/assets/hero-bg-large.png"
          alt="Background"
          className="w-full h-full object-cover opacity-80 dark:opacity-30 transition-transform duration-75 ease-out"
          style={{ transform: `scale(${scale})` }}
          draggable="false"
        />
        {/* Fade to white/black at bottom for seamless transition */}
        <div className="absolute inset-x-0 bottom-0 h-64 bg-gradient-to-t from-white dark:from-black to-white/0 dark:to-transparent" />
        {/* Nav readability gradient */}
        <div className="absolute inset-x-0 top-0 h-32 bg-gradient-to-b from-white/90 dark:from-black/90 to-transparent" />
      </div>

      <div className="relative max-w-[1200px] mx-auto text-center w-full z-10 px-6 pt-20">
        <div
          ref={ref}
          className={`transition-all duration-1000 ease-out transform ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-20'}`}
        >
          <div className="inline-block mb-6 px-4 py-1.5 rounded-full border border-black/5 dark:border-white/10 bg-white/40 dark:bg-black/40 backdrop-blur-md text-[11px] font-semibold uppercase tracking-widest text-zinc-600 dark:text-zinc-400 shadow-sm">
            Open Source • Distributed • Secure
          </div>

          <h1 className="text-7xl md:text-9xl lg:text-[10rem] font-bold tracking-tighter mb-8 leading-[0.85] text-zinc-900 dark:text-white drop-shadow-sm flex flex-col items-center">
            <span>Distributed.</span>
            <span className="flex items-center justify-center mt-2">
              {"Unlimited.".split("").map((char, i) => (
                <span
                  key={i}
                  className="inline-block will-change-transform"
                  style={{
                    transform: `translateY(-${scrollY * ((12 - i) * 0.15)}px)`,
                    filter: `blur(${scrollY * ((12 - i) * 0.01)}px)`
                  }}
                >
                  <span
                    className="inline-block animate-letter-rise bg-[linear-gradient(8deg,#ffffff_0%,#818cf8_50%,#ffffff_100%)] bg-clip-text text-transparent pb-4"
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

          <p className="text-2xl md:text-3xl font-medium text-zinc-600 dark:text-zinc-300 max-w-2xl mx-auto mb-12 tracking-tight leading-snug">
            Turn your idle Mac into build credits.
            <br className="hidden md:block" />
            Build your Expo apps for free.
          </p>

          <div className="flex flex-col items-center gap-10">
            <div className="flex flex-col sm:flex-row items-center justify-center gap-5">
              <a href="#get-started" className="px-10 py-5 rounded-full bg-zinc-900 dark:bg-white text-white dark:text-black text-xl font-bold tracking-tight hover:scale-105 transition-transform duration-300 shadow-xl hover:shadow-2xl">
                Start Earning
              </a>
              <a href="#how-it-works" className="px-10 py-5 rounded-full bg-white/50 dark:bg-black/50 backdrop-blur-md border border-zinc-200 dark:border-zinc-800 text-zinc-900 dark:text-white text-xl font-bold tracking-tight hover:bg-white/80 dark:hover:bg-black/80 transition-all duration-300">
                How it works
              </a>
            </div>

            <NetworkHUD />
          </div>
        </div>
      </div>
    </section>
  );
}

import { NetworkGlobe } from "./components/NetworkGlobe";

// ... existing imports ...

// ... existing App component ...

// ... existing Nav component ...

// ... existing Hero component ...

function BentoGrid() {
  const { ref: headerRef, isVisible: headerVisible } = useScrollReveal();

  return (
    <section id="features" className="py-32 bg-white dark:bg-black relative z-10">
      <div className="max-w-[1200px] mx-auto px-6">
        <div ref={headerRef} className={`transition-all duration-1000 ease-out transform ${headerVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-10'}`}>
          <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-4 text-center">
            Power in numbers.
          </h2>
          <p className="text-xl text-zinc-500 text-center max-w-2xl mx-auto mb-16">
            A decentralized architecture designed for privacy, speed, and fairness.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 auto-rows-[400px]">

          {/* Card 1: CPU (Large) */}
          <BentoCard
            colSpan="md:col-span-2"
            title="Idle Compute."
            subtitle="Your Mac sleeps while you grab coffee. Put that M-series chip to work."
            image="/assets/feature-cpu.png"
            dark
            delay={100}
          />

          {/* Card 2: Security (Tall) */}
          <BentoCard
            colSpan="md:col-span-1"
            title="VM Isolated."
            subtitle="Hypervisor safety."
            image="/assets/feature-security.png"
            delay={200}
          />

          {/* Card 3: Network (Full Width) */}
          <BentoCard
            colSpan="md:col-span-3"
            title="Community Mesh."
            subtitle="No servers to manage. No cloud bills. Just a peer-to-peer build network built by Expo developers just like you."
            align="center"
            delay={300}
          />
        </div>
      </div>
    </section>
  );
}

function BentoCard({ colSpan, title, subtitle, image, dark, align = "left", delay = 0 }: { colSpan: string, title: string, subtitle: string, image?: string, dark?: boolean, align?: "left" | "center", delay?: number }) {
  const { ref, isVisible } = useScrollReveal();

  return (
    <div
      ref={ref}
      style={{ transitionDelay: `${delay}ms` }}
      className={`relative group overflow-hidden rounded-[2rem] border border-zinc-200 dark:border-zinc-800 ${colSpan} ${dark ? 'bg-black text-white' : 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-white'} transition-all duration-1000 transform ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-20'} hover:shadow-2xl`}
    >
      <div className="absolute inset-0 z-0 overflow-hidden">
        {image ? (
          <img src={image} className="w-full h-full object-cover opacity-90 group-hover:scale-105 transition-transform duration-1000 ease-out" alt={title} />
        ) : (
          <NetworkGlobe />
        )}
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

function Step({ num, title, desc, side }: { num: string, title: string, desc: string, side: "left" | "right" }) {
  const { ref, isVisible } = useScrollReveal();

  return (
    <div ref={ref} className={`relative flex flex-col md:flex-row gap-12 items-start transition-all duration-1000 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-20'}`}>
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

function GetStarted() {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="get-started" className="py-32 bg-white dark:bg-zinc-950 px-6">
      <div
        ref={ref}
        className={`max-w-[980px] mx-auto text-center transition-all duration-1000 transform ${isVisible ? 'opacity-100 scale-100' : 'opacity-0 scale-95'}`}
      >
        <h2 className="text-4xl md:text-6xl font-semibold tracking-tighter mb-8 text-zinc-900 dark:text-white">
          Ready to deploy?
        </h2>
        <p className="text-xl text-zinc-500 mb-12 font-medium">Open source. MIT Licensed. Yours forever.</p>

        <div className="bg-zinc-50 dark:bg-zinc-900/50 rounded-2xl border border-zinc-200 dark:border-zinc-800 p-8 shadow-2xl max-w-2xl mx-auto text-left group hover:border-indigo-500/50 transition-colors duration-500">
          <div className="flex gap-2 mb-6 border-b border-zinc-200 dark:border-zinc-800 pb-4">
            <div className="w-3 h-3 rounded-full bg-red-500" />
            <div className="w-3 h-3 rounded-full bg-yellow-500" />
            <div className="w-3 h-3 rounded-full bg-green-500" />
          </div>
          <div className="font-mono text-sm space-y-4">
            <div className="flex gap-4 items-center">
              <span className="text-indigo-500 font-bold select-none">❯</span>
              <span className="text-zinc-700 dark:text-zinc-300">git clone https://github.com/expo/expo-free-agent</span>
            </div>
            <div className="flex gap-4 items-center">
              <span className="text-indigo-500 font-bold select-none">❯</span>
              <span className="text-zinc-700 dark:text-zinc-300">cd expo-free-agent && bun install</span>
            </div>
            <div className="flex gap-4 items-center">
              <span className="text-indigo-500 font-bold select-none">❯</span>
              <span className="text-zinc-700 dark:text-zinc-300">bun start:worker</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="py-12 bg-zinc-50 dark:bg-black border-t border-zinc-200 dark:border-zinc-800">
      <div className="max-w-[980px] mx-auto px-6 flex flex-col md:flex-row justify-between items-center text-xs font-medium text-zinc-500 gap-4">
        <p>Before you build, you must first create the universe.</p>
        <div className="flex gap-6">
          <a href="#" className="hover:text-zinc-900 dark:hover:text-white transition-colors">GitHub</a>
          <a href="#" className="hover:text-zinc-900 dark:hover:text-white transition-colors">Twitter</a>
          <a href="#" className="hover:text-zinc-900 dark:hover:text-white transition-colors">Expo</a>
        </div>
      </div>
    </footer>
  );
}
