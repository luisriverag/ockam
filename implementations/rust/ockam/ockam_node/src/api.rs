#![allow(missing_docs)]

use minicbor::{Decode, Encode};

use crate::{Context, MessageSendReceiveOptions};
use ockam_core::api::Reply::Successful;
use ockam_core::api::{Error, Reply, Request, Response};
use ockam_core::compat::time::Duration;
use ockam_core::compat::vec::Vec;
use ockam_core::{LocalInfo, Result, Route};

/// This struct provides some support for making requests to another node
/// and receiving replies
pub struct Client {
    route: Route,
    timeout: Option<Duration>,
}

impl Client {
    /// Create a new client to send messages to a given destination
    /// A default timeout can be specified
    /// WARNING: The caller is responsible for cleaning all the resources
    ///          involved in the Route when it's no longer used (like TCP connections or Secure Channels)
    pub fn new(route: &Route, timeout: Option<Duration>) -> Self {
        Self {
            route: route.clone(),
            timeout,
        }
    }

    /// Send a request of type T and receive a reply of type R
    ///
    /// The result is a `Result<Reply<R>>` where `Reply<R>` can contain a value of type `R` but
    /// might be an error and a status code if the request was not successful.
    ///
    /// This allows to distinguish:
    ///
    ///  - communication errors
    ///  - request failures
    ///  - successes
    ///
    /// Note that a `Reply<T>` can be converted in a `Result<T>` by using the `success()?` method
    /// if one is not interested in request failures.
    pub async fn ask<T, R>(&self, ctx: &Context, req: Request<T>) -> Result<Reply<R>>
    where
        T: Encode<()>,
        R: for<'a> Decode<'a, ()>,
    {
        let bytes: Vec<u8> = self.request_with_timeout(ctx, req, self.timeout).await?;
        Response::parse_response_reply::<R>(bytes.as_slice())
    }

    /// Send a request of type T and don't expect a reply
    /// See `ask` for more information
    pub async fn tell<T>(&self, ctx: &Context, req: Request<T>) -> Result<Reply<()>>
    where
        T: Encode<()>,
    {
        let request_header = req.header().clone();
        let bytes = self.request_with_timeout(ctx, req, self.timeout).await?;
        let (response, decoder) = Response::parse_response_header(bytes.as_slice())?;
        if !response.is_ok() {
            Ok(Reply::Failed(
                Error::from_failed_request(&request_header, &response.parse_err_msg(decoder)),
                response.status(),
            ))
        } else {
            Ok(Successful(()))
        }
    }

    /// Send a request of type T and expect an untyped reply
    /// See `ask` for more information
    pub async fn request<T>(&self, ctx: &Context, req: Request<T>) -> Result<Vec<u8>>
    where
        T: Encode<()>,
    {
        self.request_with_timeout(ctx, req, self.timeout).await
    }

    /// Send a request of type T and expect an untyped reply within a specific timeout
    /// See `ask` for more information
    pub async fn request_with_timeout<T>(
        &self,
        ctx: &Context,
        req: Request<T>,
        timeout: Option<Duration>,
    ) -> Result<Vec<u8>>
    where
        T: Encode<()>,
    {
        let (response, _) = self.request_with_local_info(ctx, req, timeout).await?;
        Ok(response)
    }

    /// Send a request of type T and expect an untyped reply within a specific timeout
    /// Additionally provide any local information added to the received message
    /// See `ask` for more information
    pub async fn ask_with_local_info<T, R>(
        &self,
        ctx: &Context,
        req: Request<T>,
        timeout: Option<Duration>,
    ) -> Result<(Reply<R>, Vec<LocalInfo>)>
    where
        T: Encode<()>,
        R: for<'a> Decode<'a, ()>,
    {
        let (bytes, local_info) = self.request_with_local_info(ctx, req, timeout).await?;
        let reply = Response::parse_response_reply::<R>(bytes.as_slice())?;
        Ok((reply, local_info))
    }

    /// Send a request of type T and expect an untyped reply within a specific timeout
    /// Additionally provide any local information added to the received message
    /// See `ask` for more information
    async fn request_with_local_info<T>(
        &self,
        ctx: &Context,
        req: Request<T>,
        timeout: Option<Duration>,
    ) -> Result<(Vec<u8>, Vec<LocalInfo>)>
    where
        T: Encode<()>,
    {
        let mut buf = Vec::new();

        req.encode(&mut buf)?;
        trace! {
            target:  "ockam_api",
            id     = %req.header().id(),
            method = ?req.header().method(),
            path   = %req.header().path(),
            body   = %req.header().has_body(),
            "sending request"
        }
        let options = if let Some(t) = timeout {
            MessageSendReceiveOptions::new().with_timeout(t)
        } else {
            MessageSendReceiveOptions::new().without_timeout()
        };

        // TODO: Check IdentityId is the same we sent message to?
        // TODO: Check response id matches request id?
        let resp = ctx
            .send_and_receive_extended::<Vec<u8>>(self.route.clone(), buf, options)
            .await?;
        let local_info = resp.local_message().local_info().to_vec();
        let body = resp.into_body()?;

        trace! {
            target:  "ockam_api",
            id     = %req.header().id(),
            method = ?req.header().method(),
            path   = %req.header().path(),
            body   = %req.header().has_body(),
            "received response"
        }

        Ok((body, local_info))
    }
}
