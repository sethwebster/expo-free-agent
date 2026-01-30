import { useEffect, Dispatch, SetStateAction } from 'react';

export function useConnectionLineRetract(
  isRemoving: boolean,
  isRetracting: boolean,
  setIsExtending: Dispatch<SetStateAction<boolean>>,
  setIsRetracting: Dispatch<SetStateAction<boolean>>
) {
  useEffect(() => {
    if (isRemoving && !isRetracting) {
      setIsExtending(false);
      setIsRetracting(true);
    }
  }, [isRemoving, isRetracting, setIsExtending, setIsRetracting]);
}
