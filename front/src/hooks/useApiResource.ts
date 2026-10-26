import { useCallback, useEffect, useRef, useState } from "react";

import { toApiError, type ApiError } from "../api";

export interface ApiResource<T> {
  data: T | null;
  loading: boolean;
  error: ApiError | null;
  reload: () => void;
}

export function useApiResource<T>(
  loader: (signal: AbortSignal) => Promise<T>,
  dependencies: unknown[],
): ApiResource<T> {
  const loaderRef = useRef(loader);
  loaderRef.current = loader;

  const [version, setVersion] = useState(0);
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError(null);

    loaderRef
      .current(controller.signal)
      .then((result) => {
        if (controller.signal.aborted) return;
        setData(result);
        setLoading(false);
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(toApiError(reason));
        setLoading(false);
      });

    return () => controller.abort();
  }, [...dependencies, version]);

  const reload = useCallback(() => setVersion((current) => current + 1), []);

  return { data, loading, error, reload };
}
