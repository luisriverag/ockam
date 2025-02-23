use crate::tokio::runtime::Runtime;
use crate::{debugger, Context, Executor};
use ockam_core::compat::sync::Arc;
use ockam_core::flow_control::FlowControls;
#[cfg(feature = "std")]
use ockam_core::OpenTelemetryContext;

/// A minimal worker implementation that does nothing
pub struct NullWorker;

impl ockam_core::Worker for NullWorker {
    type Context = Context;
    type Message = (); // This message type is never used
}

/// Start a node with a custom setup configuration
///
/// The `start_node()` function wraps this type and simply calls
/// `NodeBuilder::default()`.  Varying use-cases should use the
/// builder API to customise the underlying node that is created.
pub struct NodeBuilder {
    logging: bool,
    exit_on_panic: bool,
    rt: Option<Arc<Runtime>>,
}

impl Default for NodeBuilder {
    fn default() -> Self {
        Self::new()
    }
}

impl NodeBuilder {
    /// Create a node
    pub fn new() -> Self {
        Self {
            logging: true,
            exit_on_panic: true,
            rt: None,
        }
    }

    /// Disable logging on this node
    pub fn no_logging(self) -> Self {
        Self {
            logging: false,
            exit_on_panic: self.exit_on_panic,
            rt: self.rt,
        }
    }

    /// Enable logging on this node
    pub fn with_logging(self, logging: bool) -> Self {
        Self {
            logging,
            exit_on_panic: self.exit_on_panic,
            rt: self.rt,
        }
    }

    /// Disable exit on panic on this node
    pub fn no_exit_on_panic(self) -> Self {
        Self {
            logging: self.logging,
            exit_on_panic: false,
            rt: self.rt,
        }
    }

    /// Use a specific runtime
    pub fn with_runtime(self, rt: Arc<Runtime>) -> Self {
        Self {
            logging: self.logging,
            exit_on_panic: self.exit_on_panic,
            rt: Some(rt),
        }
    }

    /// Consume this builder and yield a new Ockam Node
    #[inline]
    pub fn build(self) -> (Context, Executor) {
        if self.logging {
            setup_tracing();
        }

        // building a node should happen only once per process
        // to create the Context and the Executor (containing the Router)
        // Since the Executor is used to run async functions we need to catch
        // any panic raised by those functions and exit the current process in case this happens.
        // Otherwise the Executor might stay blocked on the Router execution.
        #[cfg(feature = "std")]
        if self.exit_on_panic {
            std::panic::set_hook(Box::new(|panic_info| {
                let message1 = format!("A fatal error occurred: {panic_info}.");
                let message2 = "Please report this issue, with a copy of your logs, to https://github.com/build-trust/ockam/issues.";
                error!(message1);
                error!(message2);
                println!("{}", message1);
                println!("{}", message2);
                std::process::exit(1);
            }));
        }

        info!("Initializing ockam node");

        // Shared instance of FlowControls
        let flow_controls = FlowControls::new();

        let rt = self.rt.unwrap_or_else(|| {
            #[cfg(feature = "std")]
            {
                Arc::new(
                    tokio::runtime::Builder::new_multi_thread()
                        // Using a lower stack size than the default (1MB),
                        // this helps improve the cache hit ratio and reduces
                        // the memory footprint.
                        // Can be increased if needed.
                        .thread_stack_size(1024 * 1024)
                        .enable_all()
                        .build()
                        .expect("cannot initialize the tokio runtime"),
                )
            }
            #[cfg(not(feature = "std"))]
            Arc::new(Runtime::new().expect("cannot initialize the tokio runtime"))
        });

        #[cfg(feature = "watchdog")]
        {
            let watchdog = crate::watchdog::TokioRuntimeWatchdog::new();
            watchdog.start_watchdog_loop(&rt);
        }

        let handle = rt.handle().clone();
        let exe = Executor::new(rt, &flow_controls);

        let router = exe.router().upgrade().unwrap();

        // The root application worker needs a mailbox and relay to accept
        // messages from workers, and to buffer incoming transcoded data.

        let (ctx, sender, _) = Context::create_app_context(
            handle.clone(),
            Arc::downgrade(&router),
            &flow_controls,
            #[cfg(feature = "std")]
            OpenTelemetryContext::current(),
        );

        debugger::log_inherit_context("NODE", &ctx, &ctx);

        // Register this mailbox handle with the executor
        router
            .add_worker(
                ctx.mailboxes(),
                sender,
                true,
                Default::default(),
                ctx.mailbox_count(),
            )
            .expect("router initialization failed");

        // Then return the root context and executor
        (ctx, exe)
    }
}

/// Utility to setup tracing-subscriber from the environment.
///
/// Does nothing if the `no_init_tracing` feature is enabled (for now -- this
/// should be improved, though).
fn setup_tracing() {
    #[cfg(feature = "std")]
    {
        use tracing_subscriber::{filter::LevelFilter, fmt, prelude::*, EnvFilter};
        static ONCE: std::sync::Once = std::sync::Once::new();
        ONCE.call_once(|| {
            let filter = EnvFilter::try_from_env("OCKAM_LOG_LEVEL").unwrap_or_else(|_| {
                EnvFilter::default()
                    .add_directive(LevelFilter::INFO.into())
                    .add_directive("ockam_node=info".parse().unwrap())
            });
            // Ignore failure, since we may init externally.
            let _ = tracing_subscriber::registry()
                .with(filter)
                .with(tracing_error::ErrorLayer::default())
                .with(fmt::layer())
                .try_init();
        });
    }
}
