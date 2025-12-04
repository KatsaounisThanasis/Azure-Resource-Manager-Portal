function Skeleton({ className = '', variant = 'text' }) {
  const baseClass = 'animate-pulse bg-gray-200 rounded';

  const variantClasses = {
    text: 'h-4 w-full',
    title: 'h-8 w-3/4',
    circle: 'rounded-full h-12 w-12',
    rectangle: 'h-32 w-full',
    card: 'h-48 w-full',
    button: 'h-10 w-24'
  };

  const variantClass = variantClasses[variant] || variantClasses.text;

  return <div className={`${baseClass} ${variantClass} ${className}`} />;
}

function SkeletonCard() {
  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6 space-y-4">
      <div className="flex items-start space-x-4">
        <Skeleton variant="circle" />
        <div className="flex-1 space-y-2">
          <Skeleton variant="title" className="w-1/2" />
          <Skeleton variant="text" className="w-3/4" />
        </div>
      </div>
      <div className="space-y-2">
        <Skeleton variant="text" />
        <Skeleton variant="text" className="w-5/6" />
      </div>
      <div className="flex space-x-2">
        <Skeleton variant="button" />
        <Skeleton variant="button" />
      </div>
    </div>
  );
}

function SkeletonList({ count = 3 }) {
  return (
    <div className="space-y-4">
      {Array.from({ length: count }).map((_, index) => (
        <SkeletonCard key={index} />
      ))}
    </div>
  );
}

export { Skeleton, SkeletonCard, SkeletonList };
export default Skeleton;
